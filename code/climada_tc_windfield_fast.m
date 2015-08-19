function res = climada_tc_windfield_fast(tc_track, centroids, equal_timestep, silent_mode, check_plot)
% TC windfield calculation
% NAME:
%   climada_tc_windfield
% PURPOSE:
%   given a TC track (lat/lon,CentralPressure,MaxSustainedWind), calculate
%   the wind field at locations (=centroids)
%
%   mainly called from: see climada_tc_hazard_set
%
%   Notre: due to improvements also in climada_tc_windfield, this 'fast'
%   version seems in fact not to be faster any more, hence kept for
%   comparison, but not used, see climada_tc_windfield
%
% CALLING SEQUENCE:
%   climada_tc_windfield(tc_track,centroids,equal_timestep,silent_mode)
% EXAMPLE:
%   climada_tc_windfield
%   plot windfield:
%   climada_tc_windfield(tc_track(1411), centroids,1,1,1)
% INPUTS:
%   tc_track: a structure with the track information:
%       tc_track.lat
%       tc_track.lon
%       tc_track.MaxSustainedWind: maximum sustained wind speed (one-minute)
%       tc_track.MaxSustainedWindUnit as 'kn', 'mph', 'm/s' or 'km/h'
%       tc_track.CentralPressure: optional
%       tc_track.Celerity: translational (forward speed) of the hurricane.
%           optional, calculated from lat/lon if missing
%       tc_track.TimeStep: optional, only needed if Celerity needs to be
%           calculated, 6h assumed as default
%       tc_track.Azimuth: the forward moving angle, calculated if not given
%           to ensure consistency, it is even suggested not to pass Azimuth
%       tc_track.yyyy: 4-digit year, optional
%       tc_track.mm: month, optional
%       tc_track.dd: day, optional
%       tc_track.ID_no: unique ID, optional
%       tc_track.name: name, optional
%       tc_track.SaffSimp: Saffir-Simpson intensity, optional
%   centroids: a structure with the centroids information
%       centroids.lat: the latitude of the centroids
%       centroids.lon: the longitude of the centroids
% OPTIONAL INPUT PARAMETERS:
%   equal_timestep: if set=1 (default), first interpolate the track to a common
%       timestep, if set=0, no equalization of TC track data (not recommended)
%   silent_mode: if =1, do not write to stdout unless severe warning
% OUTPUTS:
%   res.gust: the windfield [m/s] at all centroids
%       the single-character variables refer to the Pioneer offering circular
%       that's why we kept these short names (so one can copy the OC for
%       documentation)
%   res.lat: the latitude of the centroids
%   res.lon: the longitude of the centroids
% RESTRICTIONS:
% MODIFICATION HISTORY:
% David N. Bresch, david.bresch@gmail.com, 20090728
% David N. Bresch, david.bresch@gmail.com, 20150103, not faster than climada_tc_windfield any more
% David N. Bresch, david.bresch@gmail.com, 20150819, climada_global.centroids_dir introduced
%-


global climada_global
if ~climada_init_vars, return; end
if ~exist('tc_track'      , 'var'), tc_track       = []; end
if ~exist('centroids'     , 'var'), centroids      = []; end
if ~exist('equal_timestep', 'var'), equal_timestep = 1; end
if ~exist('silent_mode'   , 'var'), silent_mode    = 0; end
if ~exist('check_plot'    , 'var'), check_plot     = 0; end

if check_plot == 0
    check_printplot = 0;
else
    check_printplot = 0;
    %check_printplot = 1;
end

% prompt for tc_track if not given
if isempty(tc_track)
    tc_track             = [climada_global.data_dir filesep 'tc_tracks' filesep '*.mat'];
    tc_track_default     = [climada_global.data_dir filesep 'tc_tracks' filesep 'Select PROBABILISTIC tc track .mat'];
    [filename, pathname] = uigetfile(tc_track, 'Select PROBABILISTIC tc track set:',tc_track_default);
    if isequal(filename,0) || isequal(pathname,0)
        return; % cancel
    else
        tc_track = fullfile(pathname,filename);
    end
end

% load the tc track set, if a filename has been passed
if ~isstruct(tc_track)
    tc_track_file = tc_track;
    tc_track      = [];
    vars = whos('-file', tc_track_file);
    load(tc_track_file);
    if ~strcmp(vars.name,'tc_track')
        tc_track = eval(vars.name);
        clear (vars.name)
    end
    prompt   ='Type specific No. of track to print windfield [e.g. 1, 10, 34, 1011]:';
    name     =' No. of track';
    defaultanswer = {'1011'};
    answer = inputdlg(prompt,name,1,defaultanswer);
    track_no = str2double(answer{1});
    tc_track = tc_track(track_no);
    check_plot = 1;
end

% prompt for centroids if not given
if isempty(centroids)
    centroids            = [climada_global.centroids_dir filesep '*.mat'];
    [filename, pathname] = uigetfile(centroids, 'Select centroids:');
    if isequal(filename,0) || isequal(pathname,0)
        return; % cancel
    else
        centroids = fullfile(pathname,filename);
    end
end

% load the centroids, if a filename has been passed
if ~isstruct(centroids)
    centroids_file = centroids;
    centroids      = [];
    vars = whos('-file', centroids_file);
    load(centroids_file);
    if ~strcmp(vars.name,'centroids')
        centroids = eval(vars.name);
        clear (vars.name)
    end
end


res = []; % init output


% PARAMETERS
% threshold above which we calculate the windfield
wind_threshold = 0; % in m/s, default=0

% treat the extratropical transition celerity exceeding vmax problem
treat_extratropical_transition = 0; % default=0, since non-standard iro Holland

% whether we plot the windfield (more for debugging this code)
% (you rather plot the output of this routine in your own code than setting this flag, for speed reasons)
% check_plot = 0; % default=0 
tc_track_ori = tc_track;

if equal_timestep
    if ~silent_mode,fprintf('NOTE: tc_track refined (1 hour timestep) prior to windfield calculation\n');end
    tc_track = climada_tc_equal_timestep(tc_track); % make equal timesteps
end

% calculate MaxSustainedWind if only CentralPressure given
if ~isfield(tc_track,'MaxSustainedWind') && isfield(tc_track,'CentralPressure')
    tc_track.MaxSustainedWind = tc_track.CentralPressure*0; % init
end

% check validity of MaxSustainedWind
if isfield(tc_track,'MaxSustainedWind')
    tc_track.MaxSustainedWind(isnan(tc_track.MaxSustainedWind))=0; % NaN --> 0
end

% to convert to km/h
switch tc_track.MaxSustainedWindUnit 
    case 'kn'
        tc_track.MaxSustainedWind = tc_track.MaxSustainedWind*1.15*1.61;
    case 'kt'
        tc_track.MaxSustainedWind = tc_track.MaxSustainedWind*1.15*1.61;
    case 'mph'
        tc_track.MaxSustainedWind = tc_track.MaxSustainedWind/0.62137;
    case 'm/s'
        tc_track.MaxSustainedWind = tc_track.MaxSustainedWind*3.6;
    otherwise
        % already km/h
end;
tc_track.MaxSustainedWindUnit = 'km/h'; % after conversion

% calculate MaxSustainedWind if only CentralPressure given
zero_wind_pos = find(tc_track.MaxSustainedWind==0);
if ~isempty(zero_wind_pos)
    if ~silent_mode,fprintf('calculating MaxSustainedWind (%i of %i nodes) ...\n',length(zero_wind_pos),length(tc_track.MaxSustainedWind));end
    % hard-wired fit parameters, see climada_bom_check_Pwind_relation to get
    % these P-values (that's why they are NOT in the Parameter section above)
    P1 =   -0.0000709379; % all P-values to result in km/h windspeed
    P2 =    0.1952888100;
    P3 = -180.5843850867;
    P4 = 56284.046256966;
    tc_track.MaxSustainedWind(zero_wind_pos) =...
        P1*tc_track.CentralPressure(zero_wind_pos).^3 +...
        P2*tc_track.CentralPressure(zero_wind_pos).^2 +...
        P3*tc_track.CentralPressure(zero_wind_pos) + P4;
    % treat bad pressure data
    invalid_pos = find(tc_track.CentralPressure<700); 
    if ~isempty(invalid_pos), tc_track.MaxSustainedWind(invalid_pos) = 0; end;
    % treat where pressure shows no wind
    filled_pos = find(tc_track.CentralPressure>=1013); 
    if ~isempty(filled_pos),tc_track.MaxSustainedWind(filled_pos)=0;end;

    tc_track.zero_MaxSustainedWind_pos = zero_wind_pos; % to store
end % length(zero_wind_pos)>0

if isfield(tc_track,'Celerity')
    switch tc_track.CelerityUnit % to convert to km/h
        case 'kn'
            tc_track.Celerity = tc_track.Celerity*1.15*1.61;
        case 'kt'
            tc_track.Celerity = tc_track.Celerity*1.15*1.61;
        case 'mph'
            tc_track.Celerity = tc_track.Celerity/0.62137;
        case 'm/s'
            tc_track.Celerity = tc_track.Celerity*3.6;
        otherwise
            % already km/h
    end;
    tc_track.CelerityUnit = 'km/h'; % after conversion
end

% Azimuth - always recalculate to avoid bad troubles (interpolating over North... other meaning of directions)
% calculate km distance between nodes
ddx                       = diff(tc_track.lon).*cos( (tc_track.lat(2:end)-0.5*diff(tc_track.lat)) /180*pi);
ddy                       = diff(tc_track.lat);
tc_track.Azimuth          = atan2(ddy,ddx)*180/pi; % in degree
tc_track.Azimuth          = mod(-tc_track.Azimuth+90,360); % convert wind such that N is 0, E is 90, S is 180, W is 270
tc_track.Azimuth          = [tc_track.Azimuth(1) tc_track.Azimuth];
% %%to check Azimuth
% subplot(2,1,1);
% plot(tc_track.lon,tc_track.lat,'-r');
% plot(tc_track.lon,tc_track.lat,'xr');
% subplot(2,1,2)
% plot(tc_track.Azimuth);title('calculated Azimuth');ylabel('degree (N=0, E=90)');
% return

% calculate forward speed (=celerity, km/h) if not given
if ~isfield(tc_track,'Celerity')
    % calculate km distance between nodes
    dd = 111.1 * sqrt(  ddy.^2 + ddx .^2 );
    %dd_in_miles=dd*0.62137; % just if needed
    tc_track.Celerity          = dd./tc_track.TimeStep(1:length(dd)); % avoid troubles with TimeStep sometimes being one longer
    tc_track.Celerity          = [tc_track.Celerity(1) tc_track.Celerity];
end

% keep only windy nodes
pos = find(tc_track.MaxSustainedWind > (wind_threshold*3.6)); % cut-off in km/h
if ~isempty(pos)
    tc_track.lon              = tc_track.lon(pos);
    tc_track.lat              = tc_track.lat(pos);
    tc_track.MaxSustainedWind = tc_track.MaxSustainedWind(pos);
    tc_track.Celerity         = tc_track.Celerity(pos);
    tc_track.Azimuth          = tc_track.Azimuth(pos);
end

cos_tc_track_lat = cos(tc_track.lat/180*pi);
centroid_count   = length(centroids.lat);
res.gust         = spalloc(centroid_count,1,ceil(centroid_count*0.1));

% % radius of max wind (km)
R_min = 30; 
R_max = 75;
tc_track.R                = ones(1,length(tc_track.lon))*R_min;
trop_lat                  = abs(tc_track.lat) > 24;
tc_track.R(trop_lat)      = tc_track.R(trop_lat)+2.5*(tc_track.lat(trop_lat)-24);
extratrop_lat             = abs(tc_track.lat) > 42;
tc_track.R(extratrop_lat) = R_max;

              
% add further fields (for climada use)
if isfield(centroids,'OBJECTID')   , res.OBJECTID = centroids.OBJECTID;    end
if isfield(centroids,'centroid_ID'), res.ID       = centroids.centroid_ID; end

res.lat = centroids.lat;
res.lon = centroids.lon;

% find closest track node to every centroid, and calculate distance in km
C_lonlat = [centroids.lon' centroids.lat']; 

% [lon_max pos1] = max(tc_track.lon);
% [lon_min pos2] = min(tc_track.lon);
% [lat_max pos3] = max(tc_track.lat);
% [lat_min pos4] = min(tc_track.lat);
% t_nodes        = [lon_max tc_track.lat(pos1); lon_min tc_track.lat(pos2); tc_track.lon(pos3) lat_max ; tc_track.lon(pos4) lat_min];
dist_km        = climada_geo_distance(0,42,1,42)/1000;
close_enough   = [];
for n_i = 1:size(tc_track.lon,2) %size(t_nodes,1)
    dist_max = bsxfun(@minus, C_lonlat, [tc_track.lon(n_i) tc_track.lat(n_i)]);
    dist_max = sqrt(sum(dist_max.^2,2));
    %dist_max = bsxfun(@minus, C_lonlat, t_nodes(n_i,:));
    %dist_max = sum(abs(dist_max),2);
    close_enough_1 = abs(dist_max) < 5*max(tc_track.R) /dist_km;
    close_enough = unique([close_enough; find(close_enough_1)]);
end


if ~isempty(close_enough)
    % find closest track node to every centroid, and calculate distance in km
    C_lonlat = C_lonlat(close_enough,:);
    T_lonlat = [tc_track.lon' tc_track.lat']; 
    % make C_lonlat into n-by-1-by-3 already 
    C_lonlat         = permute(C_lonlat,[1 3 2]); 
    cos_tc_track_lat = cos(tc_track.lat/180*pi);
    %distance in km
    allDist_1          = bsxfun(@minus, C_lonlat, permute(T_lonlat,[3 1 2])); 
    allDist_1(:,:,1)   = bsxfun(@times, allDist_1(:,:,1), cos_tc_track_lat); 
    allDist_1          = sqrt(sum(allDist_1.^2,3))*111.12; 
    [MinDist1 minpos1] = min(allDist_1,[],2); 
    
    MinDist(close_enough) = MinDist1;
    minpos(close_enough)  = minpos1;
        
    cen_in = close_enough';
else
    cen_in = [];
end


tic;
for centroid_i = cen_in % 1:centroid_count % now loop over all centroids
    
    % the single-character variables refer to the Pioneer offering circular
    % that's why we kept these short names (so one can copy the OC for documentation)

    %closest node and distance to closest node
    node_i = minpos(centroid_i);
    D      = MinDist(centroid_i); %in km
  
    % radius of maximum wind
    R = tc_track.R(node_i);

    if D<10*R % close enough to have an impact
        %%if D<5*R % faster method for non-Pioneer applications

        % calculate angle to node to determine left/right of track
        ddx          = (res.lon(centroid_i) - tc_track.lon(node_i))*cos(tc_track.lat(node_i)/180*pi);
        ddy          = (res.lat(centroid_i) - tc_track.lat(node_i));
        node_Azimuth = atan2(ddy,ddx)*180/pi; % in degree
        node_Azimuth = mod(-node_Azimuth+90,360); % convert wind such that N is 0, E is 90, S is 180, W is 270
        %res.node_Azimuth(centroid_i) = node_Azimuth; % to store
        
        M  = tc_track.MaxSustainedWind(node_i);

        % celerity
        if mod(node_Azimuth-tc_track.Azimuth(node_i)+360,360)<180
            % right of track
            T =  tc_track.Celerity(node_i);
        else
            % left of track
            T = -tc_track.Celerity(node_i);
        end;
        % switch sign for Southern Hemisphere
        if tc_track.lat(node_i)<0
            %T = -T;
        end 

        if treat_extratropical_transition
            % special to avoid unrealistic celerity after extratropical transition
            max_T_fact = 0.0;
            T_fact     = 1.0; % init
            if abs(node_lat) > 35, T_fact = 1.0 + (max_T_fact-1.0)*(abs(node_lat)-35)/(42-35);end;
            if abs(node_lat) > 42, T_fact = max_T_fact; end;
            T = sign(T)*min(abs(T),abs(M)); % first, T never exceeds M
            T = T*T_fact; % reduce T influence by latitude
        end;
        
        if D<=R
            % in the inner core
            S = min(M, M+2*T*D/R); 
        
        elseif D<10*R 
            % in the outer core    
            S = max( (M-abs(T))*( R^1.5 * exp( 1-R^1.5/D^1.5 )/D^1.5) + T, 0);  
        else
            S = 0; % well, see also check before, hence never reached
        end % D<10*R
        
        % G now in m/s, peak gust
        %(gust (few seconds) is about 27% higher than a 1 min sustained wind
        %http://www.prh.noaa.gov/cphc/pages/FAQ/Winds_and_Energy.php
        gust = max((S/3.6)*1.27,0); 
        if isfield(centroids,'wkn_fct')
            res.gust(centroid_i) = gust*centroids.wkn_fct(centroid_i); 
        else
            res.gust(centroid_i) = gust; 
        end
        
    end % D<10*R
end % centroid_i

title_str = [tc_track.name ', ' datestr(tc_track.datenum(1))];
if ~silent_mode,fprintf('%f secs for %s windfield\n',toc,deblank(title_str));end


%--------------
%% FIGURE
%--------------
if check_plot
    fprintf('preparing footprint plot\n')

        
    %scale figure according to range of longitude and latitude
    scale  = max(centroids.lon) - min(centroids.lon);
    scale2 =(max(centroids.lon) - min(centroids.lon))/...
            (min(max(centroids.lat),60)-max(min(centroids.lat),-50));
    height = 0.5;
    if height*scale2 > 1.2; height = 1.2/scale2; end
    fig = climada_figuresize(height,height*scale2+0.15);
    if ~isempty(cen_in)
        % create gridded values
        [X, Y, gridded_VALUE] = climada_gridded_VALUE(full(res.gust), centroids);
        gridded_max       = max(max(gridded_VALUE));
        gridded_max_round = 90;
        %gridded_max_round = 70;

        contourf(X, Y, full(gridded_VALUE),...
                 0:10:gridded_max_round,'edgecolor','none')
    end
    hold on
    climada_plot_world_borders(0.7)
    climada_plot_tc_track_stormcategory(tc_track_ori);   
    %centroids
    %plot(centroids.lon, centroids.lat, '+r','MarkerSize',0.8,'linewidth',0.1)
    
    axis equal
    axis([min(centroids.lon)-scale/30  max(centroids.lon)+scale/30 ...
          max(min(centroids.lat),-50)-scale/30  min(max(centroids.lat),60)+scale/30])
    if ~isempty(cen_in)
        %plot(centroids.lon(cen_in), centroids.lat(cen_in), 'ob','MarkerSize',3,'linewidth',1)
        caxis([0 gridded_max_round])
        cmap_= [1.0000    1.0000    1.0000;
                0.8100    0.8100    0.8100;
                0.6300    0.6300    0.6300;
                1.0000    0.8000    0.2000;
                0.9420    0.6667    0.1600;
                0.8839    0.5333    0.1200;
                0.8259    0.4000    0.0800;
                0.7678    0.2667    0.0400;
                0.7098    0.1333         0];
        colormap(cmap_)
        colorbartick           = [0:10:gridded_max_round round(gridded_max)];
        colorbarticklabel      = num2cell(colorbartick);
        colorbarticklabel{end} = [num2str(gridded_max,'%10.2f') 'max'];
        colorbarticklabel{end} = [int2str(gridded_max)          'max'];
        t = colorbar('YTick',colorbartick,'yticklabel',colorbarticklabel);
        set(get(t,'ylabel'),'String', 'Wind speed (m s^{-1})','fontsize',8);
    end
    xlabel('Longitude','fontsize',8)
    ylabel('Latitude','fontsize',8)
    title(title_str,'interpreter','none','fontsize',8)
    set(gca,'fontsize',8) 

    if isempty(check_printplot)
        choice = questdlg('print?','print');
        switch choice
        case 'Yes'
            check_printplot = 1;
        case 'No'
            check_printplot = 0;
        case 'Cancel'
            return
        end
    end

    if check_printplot %(>=1)   
        foldername = [filesep 'results' filesep 'footprint_' tc_track.name '.pdf'];
        print(fig,'-dpdf',[climada_global.data_dir foldername])
        %close
        fprintf('saved 1 FIGURE in folder %s \n', foldername);
    end
end
 
end
    
