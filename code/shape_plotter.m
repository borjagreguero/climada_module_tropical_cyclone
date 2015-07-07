function shape_plotter(shapes,label_att,lon_fieldname,lat_fieldname,varargin)
% shape_plotter
% MODULE:
%   climada core
% NAME:
%   shape_plotter
% PURPOSE:
%   easily plot shape structs containing multiple shapes
% CALLING SEQUENCE:
%   shape_plotter(shapes,label_att,varargin)
% EXAMPLE:
%   shape_plotter(shapes,'attribute name','X','Y','linewidth',2,'color','r')
%   shape_plotter(shapes,'attribute name','x','y','linewidth',2,'color','r')
% INPUTS: 
%   shapes         : struct with shape file info must have fields X and Y
% OPTIONAL INPUT PARAMETERS:
%   label_att      : the fieldname containing the string with which you wish to
%                    label each shape
%   lon_fieldname  : specify fieldname where to take lon information, default ".X"
%   lat_fieldname  : specify fieldname where to take lat information, default ".Y"
%   varargin       : any property value pair compatible with Matlab's plot func
% OUTPUTS:
% MODIFICATION HISTORY:
% Gilles Stassen, gillesstassen@hotmail.com, 18052015, init
% Lea Mueller, muellele@gmail.com, 20150607, add lon_fieldname and lat_fieldname to specify fieldnames of lon/lat coordinates
%-

global climada_global
if ~climada_init_vars; return; end

if ~exist('shapes'       ,'var'), return;             end
if ~exist('label_att'    ,'var'), label_att     = ''; end
if ~exist('lon_fieldname','var'), lon_fieldname = ''; end
if ~exist('lat_fieldname','var'), lat_fieldname = ''; end

if ~isstruct(shapes)
    shapes_file = shapes; shapes = [];
    [fP,fN,fE] = fileparts(shapes_file);
    
    if strcmp(fE,'.mat')
        load(shapes_file);
    elseif strcmp(fE,'.shp')
        shapes = climada_shaperead(shapes_file,0);
    else
        cprintf([1 0 0],'ERROR: invalid filetype\n')
        return;
    end
end

if isempty(lon_fieldname), lon_fieldname = 'X'; end
if isempty(lat_fieldname), lat_fieldname = 'Y'; end

if ~isfield(shapes,lon_fieldname) || ~isfield(shapes,lat_fieldname)
    cprintf([1 0 0],'ERROR: shapes must have attributes %s and %s\n', lon_fieldname, lat_fieldname)
    return;    
end

vararg_str = '';
if ~isempty(varargin)
    for arg_i = 1: length(varargin)
        if isnumeric(varargin{arg_i})
            vararg_str = [vararg_str ',' '[' num2str(varargin{arg_i}) ']'];
        elseif ischar(varargin{arg_i})
            vararg_str = [vararg_str ',' '''' varargin{arg_i} '''']; 
        end
    end
else
    vararg_str = ',''linewidth'',1,''color'',[81 81 81]/255';
end

eval_str = sprintf('h = plot3(shapes(shape_i).%s, shapes(shape_i).%s,Z %s);',lon_fieldname, lat_fieldname, vararg_str);
% eval_str = ['h = plot3(shapes(shape_i).X, shapes(shape_i).Y,Z' vararg_str ');'];
hold on
% legend('-DynamicLegend');

% plot each shape in struct
for shape_i = 1:length(shapes)
    eval_str_Z = sprintf('Z=ones(size(shapes(shape_i).%s)).*(1000000000000);',lon_fieldname);
    eval(eval_str_Z)
    %Z = ones(size(shapes(shape_i).X)).*(1000000000000);
    eval(eval_str);
    if ~isempty(label_att) && ischar(label_att)
        if isfield(shapes,'BoundingBox')
            c_lon = mean(shapes(shape_i).BoundingBox(:,1));
            c_lat = mean(shapes(shape_i).BoundingBox(:,2));
        else
            c_lon = mean(shapes(shape_i).X);
            c_lat = mean(shapes(shape_i).Y);
        end
        t = text(c_lon,c_lat,Z(1),shapes(shape_i).(label_att));
        set(t,'HorizontalAlignment','center');
    end
end
% eval_str = ['h = plot(shapes(end).X, shapes(end).Y' vararg_str ', ''DisplayName'', ''' name ''');'];
eval(eval_str)

% if ~isempty(name)
%     if ~isempty(get(legend,'HandleVisibility'))
%         legappend(h,name);
%     else
%         legend(h,name);
%     end
% end
