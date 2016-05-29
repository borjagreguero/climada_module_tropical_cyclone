function hazard = climada_tc_hazard_set_slow(tc_track,hazard_set_file,centroids)
% climada TC hazard event set generate
% NAME:
%   climada_tc_hazard_set
% PURPOSE:
%   SLOW, only kept for backward compatibility, see climada_tc_hazard_set
%
%   generate a tc (tropical cyclone) hazard event set
%
%   If centroids.distance2coast_km exists, the hazard intensity is only
%   calculated in the coastal_range_km (usually 200km, see PARAMETERS in
%   climada_tc_windfield) - this speeds up calculation for large countries
%   considerably.
%
%   Special: the hazard event set is stored every 100 tracks in order to
%   allow for interruption of the hazard set generation. Just re-start the
%   calculation by calling climada_tc_hazard_set with exactly the same
%   input parameters (the last track calculated is stored in hazard.track_i
%   and the field track_i is removed in the final complete hazard event set).  
%   Therefore, if you get errors such as 
%       Subscripted assignment dimension mismatch.
%       Error in climada_tc_hazard_set (line 270) % ... or nearby
%       hazard.intensity(track_i,:)     = res.gust;
%   It is VERY likely that you changed something between subsequent calls
%   (i.e. different centroids). Just delete the hazard set .mat file and run
%   climada_tc_hazard_set again.
%
%   previous: likely climada_random_walk
%   next: diverse
% CALLING SEQUENCE:
%   res=climada_tc_hazard_set_slow(tc_track,hazard_set_file,centroids)
% EXAMPLE:
%   res=climada_tc_hazard_set_slow(tc_track)
% INPUTS:
% OPTIONAL INPUT PARAMETERS:
%   tc_track: a TC track structure, or a filename of a saved one
%       details: see e.g. climada_tc_random_walk
%       > promted for if not given
%   hazard_set_file: the name (and path, optional) of the hazard set file
%       If no path provided, default path ../data/hazards is used (and name
%       can be without extension .mat). If ='NOSAVE', the hazard set is not
%       saved (but returned as output)
%       > promted for if not given
%   centroids: the variable grid centroids (see climada_centroids_read)
%       a structure with
%           lon(1,:): the longitudes
%           lat(1,:): the latitudes
%           centroid_ID(1,:): a unique ID for each centroid, simplest: 1:length(Longitude)
%       or a .mat-file which contains a centroids struct (saved by
%       climada_centroids_read) or the filename of an Excel file (the original
%       input to climada_centroids_read) which holds the centroids, in
%       which case climada_centroids_read is called.
%       OR: an entity, in which case the entity.assets.lat and
%       entity.assets.lon are used as centroids.
%       > promted for .mat or .xls filename if not given
%       NOTE: if you then select Cancel, a regular default grid is used, see hard-wired definition in code
% OUTPUTS:
%   hazard: a struct, the hazard event set, more for tests, since the
%       hazard set is stored as hazard_set_file, see code
%       lon(centroid_i): the longitude of each centroid
%       lat(centroid_i): the latitude of each centroid
%       centroid_ID(centroid_i): a unique ID for each centroid
%       peril_ID: just an ID identifying the peril, e.g. 'TC' for
%       tropical cyclone or 'ET' for extratropical cyclone
%       comment: a free comment, normally containing the time the hazard
%           event set has been generated
%       orig_years: the original years the set is based upon
%       orig_event_count: the original events
%       event_count: the total number of events in the set, including all
%           probabilistic ones, hence event_count>=orig_event_count
%       orig_event_flag(event_i): a flag for each event, whether it's an original
%           (1) or probabilistic (0) one
%       event_ID: a unique ID for each event
%       date: the creation date of the set
%       arr(event_i,centroid_i),sparse: the hazard intensity of event_i at
%           centroid_i
%       frequency(event_i): the frequency of each event
%       matrix_density: the density of the sparse array hazard.intensity
%       windfield_comment: a free comment, not in all hazard event sets
%       filename: the filename of the hazard event set (if passed as a
%           struct, this is often useful)
% MODIFICATION HISTORY:
% David N. Bresch, david.bresch@gmail.com, 20090729
% David N. Bresch, david.bresch@gmail.com, 20130506, centroids filename handling improved
% David N. Bresch, david.bresch@gmail.com, 20140421, waitbar with secs
% David N. Bresch, david.bresch@gmail.com, 20141226, optional fields in centroids added
% David N. Bresch, david.bresch@gmail.com, 20150103, equal_timestep (much) improved
% Lea Mueller, muelleleh@gmail.com, 20150420, include tc category into hazard structure
% David N. Bresch, david.bresch@gmail.com, 20150804, allow for filename without path for hazard set name on input
% David N. Bresch, david.bresch@gmail.com, 20150819, climada_global.centroids_dir
% David N. Bresch, david.bresch@gmail.com, 20150824, removed 'TCNA' from hazard.comment
% David N. Bresch, david.bresch@gmail.com, 20150906, note on a frequent issue added to header
% David N. Bresch, david.bresch@gmail.com, 20151008, NOSAVE option added
% Lea Mueller, muelleleh@gmail.com, 20151127, add hazard.scenario, default is 'no climate change'
% David N. Bresch, david.bresch@gmail.com, 20160514, -v7.3 in save added
% David N. Bresch, david.bresch@gmail.com, 20160529, renamed to climada_tc_hazard_set_slow
%-

hazard=[]; % init

% init global variables
global climada_global
if ~climada_init_vars,return;end

% check inputs
if ~exist('tc_track','var'),tc_track=[];end
if ~exist('hazard_set_file','var'),hazard_set_file=[];end
if ~exist('centroids','var'),centroids=[];end

% PARAMETERS
%
check_plot=0; % only for few tracks, please
% check_plot commented out here and in climada_tc_windfield for speedup, see code
%
% since we store the hazard as sparse array, we need an a-priory estimation
% of it's density
hazard_arr_density=0.03; % 3% sparse hazard array density (estimated)
%
% define the reference year for this hazard set
hazard_reference_year = climada_global.present_reference_year; % default for present hazard is normally 2015
%
% define the scenario name for this hazard set
% we assume no climate change when creating a hazard set from tc tracks
hazard_scenario = 'no climate change'; 
%
% whether we create the yearset (=1, grouping events into years) or not (=0)
% the yearset is only produced for original tracks, since probabilistic
% ones can be identified as following original indices +1:ens_size, with
% ens_size=(hazard.event_count/hazard.orig_event_count)-1; see climada_EDS2YDS
% Note: the yearset creation assumes tracks to be ordered by ascending year
% (that's the case for UNISYS tracks as read by climada_tc_read_unisys_database)
create_yearset=1; % default=1

% prompt for tc_track if not given
if isempty(tc_track) % local GUI
    tc_track             = [climada_global.data_dir filesep 'tc_tracks' filesep '*.mat'];
    [filename, pathname] = uigetfile(tc_track, 'Select tc track set:');
    if isequal(filename,0) || isequal(pathname,0)
        return; % cancel
    else
        tc_track=fullfile(pathname,filename);
    end
end
if ~isstruct(tc_track) % load, if filename given
    tc_track_file=tc_track;tc_track=[];
    load(tc_track_file);
    vars = whos('-file', tc_track_file);
    load(tc_track_file);
    if ~strcmp(vars.name,'tc_track')
        tc_track = eval(vars.name);
        clear (vars.name)
    end
end

% prompt for hazard_set_file if not given
if isempty(hazard_set_file) % local GUI
    hazard_set_file      = [climada_global.data_dir filesep 'hazards' filesep 'TCXX_hazard.mat'];
    [filename, pathname] = uiputfile(hazard_set_file, 'Save TC hazard set as:');
    if isequal(filename,0) || isequal(pathname,0)
        return; % cancel
    else
        hazard_set_file = fullfile(pathname,filename);
    end
end

% complete path, if missing
[fP,fN,fE]=fileparts(hazard_set_file);
if isempty(fP),hazard_set_file=[climada_global.data_dir filesep 'hazards' filesep fN fE];end

% prompt for centroids if not given
if isempty(centroids) % local GUI
    centroids_default    = [climada_global.centroids_dir filesep '*.mat'];
    %%[filename, pathname] = uigetfile(centroids_default,'Select centroids:');
    [filename, pathname] = uigetfile({'*.mat;*.xls'},'Select centroids (.mat or .xls):',centroids_default);
    if isequal(filename,0) || isequal(pathname,0)
        % TEST centroids
        fprintf('WARNING: Special mode, TEST centroids grid created in %s\n',mfilename);
        ii=0;
        for lon_i=-100:1:-50
            for lat_i=20:1:50
                ii=ii+1;
                centroids.lon(ii)=lon_i;
                centroids.lat(ii)=lat_i;
            end
        end
        centroids.centroid_ID=1:length(centroids.lon);
    else
        centroids_file=fullfile(pathname,filename);
        [~,~,fE]=fileparts(centroids_file);
        if strcmp(fE,'.xls')
            fprintf('reading centroids from %s\n',centroids_file);
            centroids=climada_centroids_read(centroids_file);
        else
            centroids=centroids_file;
        end
        
    end
end

if isfield(centroids,'assets')
    % centroids contains in fact an entity
    entity=centroids; centroids=[]; % silly switch, but fastest
    centroids.lat =entity.assets.lat;
    centroids.lon=entity.assets.lon;
    centroids.centroid_ID=1:length(entity.assets.lon);
    % treat optional fields
    if isfield(entity.assets,'distance2coast_km'),centroids.distance2coast_km=entity.assets.distance2coast_km;end
    if isfield(entity.assets,'elevation_m'),centroids.elevation_m=entity.assets.elevation_m;end
    if isfield(entity.assets,'country_name'),centroids.country_name=entity.assets.country_name;end
    if isfield(entity.assets,'admin0_name'),centroids.admin0_name=entity.assets.admin0_name;end
    if isfield(entity.assets,'admin0_ISO3'),centroids.admin0_ISO3=entity.assets.admin0_ISO3;end
    if isfield(entity.assets,'admin1_name'),centroids.admin1_name=entity.assets.admin1_name;end
    if isfield(entity.assets,'admin1_code'),centroids.admin1_code=entity.assets.admin1_code;end
    clear entity
end

if ~isstruct(centroids) % load, if filename given
    centroids_file=centroids;centroids=[];
    % complete path, if missing
    [fP,fN,fE]=fileparts(centroids_file);
    if isempty(fP),centroids_file=[climada_global.centroids_dir filesep fN fE];end
    fprintf('centroids read from %s\n',centroids_file);
    load(centroids_file); % contains centrois as a variable
end

% add tc track category (saffir-simpson)
if ~isfield(tc_track, 'category')
    tc_track = climada_tc_stormcategory(tc_track);
end

min_year   = tc_track(1).yyyy(1);
max_year   = tc_track(end).yyyy(1); % start time of track, as we otherwise might count one year too much
orig_years = max_year - min_year+1;
% fill the hazard structure
hazard.reference_year   = hazard_reference_year;
hazard.lon              = centroids.lon;
hazard.lat              = centroids.lat;
hazard.centroid_ID      = centroids.centroid_ID;
if isfield(centroids,'elevation_m'),hazard.elevation_m=centroids.elevation_m;end
hazard.orig_years       = orig_years;
hazard.orig_event_count = 0; % init
hazard.event_count      = length(tc_track);
hazard.event_ID         = 1:hazard.event_count;
hazard.category         = zeros(1,hazard.event_count);
hazard.orig_event_flag  = zeros(1,hazard.event_count);
hazard.yyyy             = zeros(1,hazard.event_count);
hazard.mm               = zeros(1,hazard.event_count);
hazard.dd               = zeros(1,hazard.event_count);
hazard.datenum          = zeros(1,hazard.event_count);
hazard.scenario         = hazard_scenario;

% allocate the hazard array (sparse, to manage memory)
hazard.intensity = spalloc(hazard.event_count,length(hazard.lon),...
    ceil(hazard.event_count*length(hazard.lon)*hazard_arr_density));

t0       = clock;
n_tracks = length(tc_track);
msgstr   = sprintf('processing %i tracks',n_tracks);
mod_step = 10; % first time estimate after 10 tracks, then every 100
if climada_global.waitbar
    fprintf('%s (updating waitbar with estimation of time remaining every 100th track)\n',msgstr);
    h        = waitbar(0,msgstr);
    set(h,'Name','Hazard TC: tropical cyclones wind');
else
    fprintf('%s\n',msgstr);
    format_str='%s';
end

if n_tracks>10000
    default_min_TimeStep=2; % speeds up calculation by factor 2
else
    default_min_TimeStep=climada_global.tc.default_min_TimeStep;
end
tc_track=climada_tc_equal_timestep(tc_track,default_min_TimeStep); % make equal timesteps

track0=1;
if exist(hazard_set_file,'file');
    load(hazard_set_file); % restore from intermediate save
    if isfield(hazard,'track_i'),track0=hazard.track_i;end
    fprintf('picking up at track %i from %s\n',track0,hazard_set_file);
end

for track_i=track0:n_tracks
    
    % calculate wind for every centroids, equal timestep within this routine
    res                             = climada_tc_windfield(tc_track(track_i),centroids,0,1,0);
    %res                             = climada_tc_windfield_fast(tc_track(track_i),centroids,0,1,check_plot);
    
    hazard.intensity(track_i,:)     = sparse(res.gust); % to be sure
    hazard.orig_event_count         = hazard.orig_event_count+tc_track(track_i).orig_event_flag;
    hazard.orig_event_flag(track_i) = tc_track(track_i).orig_event_flag;
    
    hazard.yyyy(track_i)            = tc_track(track_i).yyyy(1);
    hazard.mm(track_i)              = tc_track(track_i).mm(1);
    hazard.dd(track_i)              = tc_track(track_i).dd(1);
    hazard.datenum(track_i)         = tc_track(track_i).datenum(1);
    hazard.name{track_i}            = tc_track(track_i).name;
    hazard.category(track_i)        = tc_track(track_i).category;
    
    % if check_plot
    %     values = res.gust;
    %     values(values==0) = NaN; % suppress zero values
    %     caxis_range       = [];
    %     climada_color_plot(values,res.lon,res.lat,'none',tc_track(track_i).name,[],[],[],[],caxis_range);hold on;
    %     plot(tc_track(track_i).lon,tc_track(track_i).lat,'xk');hold on;
    %     set(gcf,'Color',[1 1 1]);
    % end
    
    % following block only for progress measurement (waitbar or stdout)
    if mod(track_i,mod_step)==0
        mod_step          = 500;
        t_elapsed_track   = etime(clock,t0)/(track_i-track0+1); % time per track
        tracks_remaining  = n_tracks-track_i;
        t_projected_sec   = t_elapsed_track*tracks_remaining;
        if t_projected_sec<60
            msgstr = sprintf('est. %3.0f sec left (%i/%i tracks)',t_projected_sec,   track_i,n_tracks);
        else
            msgstr = sprintf('est. %3.1f min left (%i/%i tracks)',t_projected_sec/60,track_i,n_tracks);
        end
        hazard.track_i=track_i;
        %if isempty(strfind(hazard_set_file,'NOSAVE')),save(hazard_set_file,'hazard');end % intermediate save
        if isempty(strfind(hazard_set_file,'NOSAVE')),save(hazard_set_file,'hazard','-v7.3');end % intermediate save, 20160514 -v7.3 added
        if climada_global.waitbar
            waitbar(track_i/n_tracks,h,msgstr); % update waitbar
        else
            fprintf(format_str,msgstr);
            format_str=[repmat('\b',1,length(msgstr)) '%s'];
        end
    end
        
end %track_i
if climada_global.waitbar
    close(h) % dispose waitbar
else
    fprintf(format_str,''); % move carriage to begin of line
end

t_elapsed = etime(clock,t0);
msgstr    = sprintf('generating %i windfields took %3.2f min (%3.4f sec/event)',length(tc_track),t_elapsed/60,t_elapsed/length(tc_track));
fprintf('%s\n',msgstr);

if isfield(hazard,'track_i'),hazard=rmfield(hazard,'track_i');end

% number of derived tracks per original one
ens_size        = hazard.event_count/hazard.orig_event_count-1;
event_frequency = 1/(orig_years*(ens_size+1));

% not transposed, just regular
hazard.frequency         = ones(1,hazard.event_count)*event_frequency;
hazard.matrix_density    = nnz(hazard.intensity)/numel(hazard.intensity);
hazard.windfield_comment = msgstr;
hazard.peril_ID          = 'TC';
hazard.filename          = hazard_set_file;
hazard.comment           = sprintf('TC hazard event set, generated %s',datestr(now));
hazard.date              = datestr(now);
hazard.units             = 'm/s';

% add optional fields
if isfield(centroids,'distance2coast_km'),hazard.distance2coast_km=centroids.distance2coast_km;end
if isfield(centroids,'elevation_m'),hazard.elevation_m=centroids.elevation_m;end
if isfield(centroids,'country_name'),hazard.country_name=centroids.country_name;end
if isfield(centroids,'admin0_name'),hazard.admin0_name=centroids.admin0_name;end
if isfield(centroids,'admin0_ISO3'),hazard.ADM0_A3=centroids.admin0_ISO3;end
if isfield(centroids,'admin1_name'),hazard.admin1_name=centroids.admin1_name;end
if isfield(centroids,'admin1_code'),hazard.admin1_code=centroids.admin1_code;end

if create_yearset
    
    % the beginner does not need to understand whats happening here ;-)
    % see climada_EDS2YDS
    t0       = clock;
    n_tracks = length(tc_track);
    msgstr   = sprintf('yearset: processing %i tracks',n_tracks);
    mod_step = 10; % first time estimate after 10 tracks, then every 100
    if climada_global.waitbar
        fprintf('%s (updating waitbar with estimation of time remaining every 100th track)\n',msgstr);
        h        = waitbar(0,msgstr);
        set(h,'Name','Hazard TC: tropical cyclones yearset');
    else
        fprintf('%s (waitbar suppressed)\n',msgstr);
        format_str='%s';
    end
    
    year_i=1; % init
    active_year=tc_track(1).yyyy(1); % first year
    event_index=[];event_count=0; % init
    
    for track_i=1:n_tracks
        
        if tc_track(track_i).yyyy(1)==active_year
            if tc_track(track_i).orig_event_flag
                % same year, add if original track
                event_count=event_count+1;
                event_index=[event_index track_i];
            end
        else
            % new year, save last year
            hazard.orig_yearset(year_i).yyyy=active_year;
            hazard.orig_yearset(year_i).event_count=event_count;
            hazard.orig_yearset(year_i).event_index=event_index;
            year_i=year_i+1;
            % reset for next year
            active_year=tc_track(track_i).yyyy(1);
            if tc_track(track_i).orig_event_flag
                % same year, add if original track
                event_count=1;
                event_index=track_i;
            end
        end
        
        % following block only for progress measurement (waitbar or stdout)
        if mod(track_i,mod_step)==0
            mod_step          = 100;
            t_elapsed_track   = etime(clock,t0)/track_i;
            tracks_remaining  = n_tracks-track_i;
            t_projected_sec   = t_elapsed_track*tracks_remaining;
            if t_projected_sec<60
                msgstr = sprintf('est. %3.0f sec left (%i/%i tracks)',t_projected_sec,   track_i,n_tracks);
            else
                msgstr = sprintf('est. %3.1f min left (%i/%i tracks)',t_projected_sec/60,track_i,n_tracks);
            end
            if climada_global.waitbar
                waitbar(track_i/n_tracks,h,msgstr); % update waitbar
            else
                fprintf(format_str,msgstr);
                format_str=[repmat('\b',1,length(msgstr)) '%s'];
            end
        end
        
    end % track_i
    
    % save last year
    hazard.orig_yearset(year_i).yyyy=active_year;
    hazard.orig_yearset(year_i).event_count=event_count;
    hazard.orig_yearset(year_i).event_index=event_index;
    
    if climada_global.waitbar
        close(h) % dispose waitbar
    else
        fprintf(format_str,''); % move carriage to begin of line
    end
    
    t_elapsed = etime(clock,t0);
    msgstr    = sprintf('generating yearset took %3.2f sec',t_elapsed);
    fprintf('%s\n',msgstr);
    
end % create_yearset

if isempty(strfind(hazard_set_file,'NOSAVE'))
    fprintf('saving TC wind hazard set as %s\n',hazard_set_file);
    save(hazard_set_file,'hazard')
end

end % climada_tc_hazard_set_slow