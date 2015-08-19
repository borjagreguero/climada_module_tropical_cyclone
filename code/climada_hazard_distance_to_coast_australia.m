function hazard = climada_hazard_distance_to_coast_australia(hazard, centroids, tc_track, check_figure)
% Weakening of hazard, namely maximum sutained wind over land depending on
% distance to coast 
% NAME:
%   climada_hazard_distance_to_coast
% PURPOSE:
%   Weakening of hazard, namely maximum sutained wind over land depending
%   on
%   previous step:  climada_tc_hazard_set
%   next step    :  climada_ELS_calc, or climada_hazard_clim_scen, diverse
% CALLING SEQUENCE:
%   hazard = climada_hazard_distance_to_coast(hazard, centroids, tc_track)
% EXAMPLE:
%   hazard = climada_hazard_distance_to_coast
% INPUTS:
%   none, if hazard, centroids or tc_track empty prompted for
% OPTIONAL INPUT PARAMETERS:
%   check_figure to create figure
% OUTPUTS:
%   same hazard structure but hazard.intensity are lower values depending on
%   distance to coast
% RESTRICTIONS:
% MODIFICATION HISTORY:
% Lea Mueller, 20121203
% David N. Bresch, david.bresch@gmail.com, 20150819, climada_global.centroids_dir introduced
%-

% init global variables
global climada_global
if ~climada_init_vars,return;end

% check inputs
if ~exist('hazard'      , 'var'), hazard       = []; end
if ~exist('centroids'   , 'var'), centroids    = []; end
if ~exist('tc_track'    , 'var'), tc_track     = []; end
if ~exist('check_figure', 'var'), check_figure = []; end

% prompt for hazard if not given
if isempty(hazard) % local GUI
    hazard               = [climada_global.data_dir filesep 'hazards' filesep '*.mat'];
    hazard_default       = [climada_global.data_dir filesep 'hazards' filesep 'choose a hazard.mat'];
    [filename, pathname] = uigetfile(hazard, 'Open existing hazard event set:',hazard_default);
    if isequal(filename,0) || isequal(pathname,0)
        return; % cancel
    else
        hazard = fullfile(pathname,filename);
    end
end
% load the hazard, if a filename has been passed
if ~isstruct(hazard)
    hazard_file = hazard;
    hazard      = [];
    load(hazard_file);
end

% prompt for centroids if not given
if isempty(centroids)
    centroids            = [climada_global.centroids_dir filesep '*.mat'];
    [filename, pathname] = uigetfile(centroids, 'Select centroids :');
    if isequal(filename,0) || isequal(pathname,0)
        return; % cancel
    else
        centroids = fullfile(pathname,filename);
    end
end
if ~isstruct(centroids) % load, if filename given
    centroids_file = centroids; centroids = [];
    vars = whos('-file', centroids_file);
    load(centroids_file);
    if ~strcmp(vars.name,'centroids')
        centroids = eval(vars.name);
        clear (vars.name)
    end
end

% check if hazard and centroids go together
if length(centroids.lon) ~= size(hazard.intensity,2)
    fprintf('%d centroids don''t match with hazard file (%d centroids). Unable to proceed.\n',...
            length(centroids.lon),  size(hazard.intensity,2))
    hazard = [];    
    return
end

% check for distance to coast information within centroids (in km)
if ~isfield(centroids,'dist_to_coast')
    centroids = climada_centroids_distance_to_coast(centroids);
end

% prompt for centroids if not given
if isempty(tc_track)
    tc_track            = [climada_global.data_dir filesep 'tc_tracks' filesep '*.mat'];
    tc_track_default    = [climada_global.data_dir filesep 'tc_tracks' filesep 'Select tc track .mat'];
    [filename, pathname] = uigetfile(tc_track, 'Select tc track set:',tc_track_default);
    if isequal(filename,0) || isequal(pathname,0)
        return; % cancel
    else
        tc_track = fullfile(pathname,filename);
    end
end
if ~isstruct(tc_track) % load, if filename given
    tc_track_file = tc_track; tc_track = [];
    vars = whos('-file', tc_track_file);
    load(tc_track_file);
    if ~strcmp(vars.name,'tc_track')
        tc_track = eval(vars.name);
        clear (vars.name)
    end
end

% calculate weakening factor depending on distance to coast (km)
A = 1;

%% FINAL FIT US
% wind_weakening(:,1) = A*exp(-centroids.dist_to_coast/700);
% wind_weakening(:,2) = A*exp(-centroids.dist_to_coast/500);
% wind_weakening(:,3) = A*exp(-centroids.dist_to_coast/150);
% wind_weakening(wind_weakening(:,1)<1.00,1) = 1.00;
% wind_weakening(wind_weakening(:,2)<0.90,2) = 0.90;
% wind_weakening(wind_weakening(:,3)<0.30,3) = 0.30;

%% FIT FOR CHINA
% wind_weakening(:,1) = A*exp(-centroids.dist_to_coast/50);
% wind_weakening(:,2) = A*exp(-centroids.dist_to_coast/15);
% wind_weakening(:,3) = A*exp(-centroids.dist_to_coast/8.5);
% wind_weakening(wind_weakening(:,1)<0.10,1) = 0.10;
% wind_weakening(wind_weakening(:,2)<0.10,2) = 0.10;
% wind_weakening(wind_weakening(:,3)<0.10,3) = 0.10;

%% NEW FIT FOR JAPAN
wind_weakening(:,1) = A*exp(-centroids.dist_to_coast/700);
wind_weakening(:,2) = A*exp(-centroids.dist_to_coast/25);
wind_weakening(:,3) = A*exp(-centroids.dist_to_coast/10.5);
wind_weakening(wind_weakening(:,1)<0.9,1) = 0.9;
wind_weakening(wind_weakening(:,2)<0.5,2) = 0.5;
wind_weakening(wind_weakening(:,3)<0.2,3) = 0.2;

if check_figure
    climada_figuresize(0.5, 0.8);
    box on
    hold on
    cmap = jet(7);
    cmap = cmap([1 2 6],:);
    set(gca,'ColorOrder',cmap);
    % h = plot( centroids.dist_to_coast, fitted_fct, '.b','markersize',5);
    colormap(cmap)
    h = plot(centroids.dist_to_coast, wind_weakening, '.','markersize',5);
    xlabel('Distance to coast (km)')
    ylabel('Weakening factor of wind intensity')
    title('Australia: Weakening of wind intensity versus distance to coast')
    % legend(h,strtok(centroids.comment,','),'location','northeast')
    legend(h,'Tropical depression and storm','Hurricane Cat. 1 and 2','Hurricane Cat. 3, 4 and 5','location','northeast')
    legend('boxoff')
    ylim([0 max(wind_weakening(:))*1.05])
    xlim([0 200])
end


% no_events    = size(hazard.intensity,1);
% % create matrix of weakening factor to go with number of events
% fitted_array = repmat(fitted_fct,no_events,1);
% 
% % combine weakening factor with original wind intensities
% hazard.intensity   = hazard.intensity.* fitted_array;

tc_cat = [tc_track.category];

%Tropical storm
cat_0  = tc_cat <= 0;
hazard.intensity_w = hazard.intensity;
hazard.intensity_w(cat_0',:) = bsxfun(@times,hazard.intensity(cat_0',:),wind_weakening(:,1)');
% Hurricane Cat. 1 2
cat_12  = tc_cat >0 & tc_cat <3;
hazard.intensity_w(cat_12',:) = bsxfun(@times,hazard.intensity(cat_12',:),wind_weakening(:,2)');
% Hurricane Cat. 3 4 5
cat_345  = tc_cat >= 3;
hazard.intensity_w(cat_345',:) = bsxfun(@times,hazard.intensity(cat_345',:),wind_weakening(:,3)');

hazard.intensity = hazard.intensity_w;
hazard     = rmfield(hazard,'arr_w');










% % initialize weakened wind intensity array
% hazard.intensity_wkn = full(hazard.intensity);
% 
% no_events    = size(hazard.intensity,1);
% t0           = clock;
% msgstr       = sprintf('Apply weakening of wind intensity depening \n on distance to coast for %d events\n', no_events);
% h            = waitbar(0, msgstr);
% mod_step     = 10; % first time estimate after 10 tracks, then every 100
% 
% for e_i = 1:no_events 
%     
%     % find centroids where wind is bigger than 0
%     cen_index = logical(full(hazard.intensity(e_i,:)));
%     %cen_index_ori = cen_index; find(cen_index_ori); find(cen_index)
%     
%     % take only centroids where distance to coast is positive
%     cen_index(fitted_fct == 1)    = 0;
%     wkn                           = fitted_fct(cen_index);
%     hazard.intensity_wkn(e_i,cen_index) = hazard.intensity(e_i,cen_index).*wkn;
%  
%     if mod(e_i, mod_step)==0
%         mod_step              = 100;
%         t_elapsed_centroids   = etime(clock,t0)/e_i;
%         events_remaining      = no_events - e_i;
%         t_projected_events    = t_elapsed_centroids * events_remaining;
%         msgstr                = sprintf('est. %i seconds left (%i events)',ceil(t_projected_events),events_remaining);
%         waitbar(e_i/no_events,h,msgstr); % update waitbar
%     end
% end
% 
% close(h); % dispose waitbar



% if check_figure
%     delta   = 2;
%     axislim = [min(centroids.lon(onLandindex))-delta  max(centroids.lon(onLandindex))+delta ...
%                min(centroids.lat (onLandindex))-delta  max(centroids.lat (onLandindex))+delta];
%     fig_relation = diff(axislim(1:2))/diff(axislim(3:4));
%     if fig_relation<1
%         fig_height = 0.6; 
%         fig_width  = fig_height*fig_relation; 
%     else
%         fig_width  = 0.8;
%         fig_height = fig_width/fig_relation; 
%     end   
%     fig = climada_figuresize(fig_height, fig_width);
%     climada_plot_world_borders
%     cbar = plotclr(centroids.lon(onLandindex), centroids.lat(onLandindex), centroids.dist_to_coast(onLandindex),...
%                    's', 2, 1, [], [], [], [], 1);
%     set(get(cbar,'ylabel'),'String', 'Distance to coast (km)','fontsize',11)
%     axis equal
%     axis(axislim)
% end

                          
                          
                          
                          
                          
                          
                          

