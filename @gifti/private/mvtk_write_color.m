function mvtk_write_color(M,filename,format, type)
% Write geometric data on disk using VTK file format (legacy/XML,ascii/binary)
% FORMAT mvtk_write(M,filename,format)
% 
% M        - data structure
% filename - output filename [Default: 'untitled']
% format   - VTK file format: legacy, legacy-ascii, legacy-binary, xml,
%            xml-ascii, xml-binary [Default: 'legacy-ascii']
% type - 'label' for .label gifti, 'scalar' for scalar data gifti
%__________________________________________________________________________
% 
% VTK File Formats Specifications:
% http://www.vtk.org/VTK/img/file-formats.pdf
% 
% Requirements: zstream, base64encode
%__________________________________________________________________________
% Copyright (C) 2015 Wellcome Trust Centre for Neuroimaging

% Guillaume Flandin
% $Id: mvtk_write.m 6520 2015-08-13 16:13:06Z guillaume $


%-Input parameters
%--------------------------------------------------------------------------
if nargin < 2 || isempty(filename), filename = 'untitled'; end
if nargin < 3 || isempty(format)
    [pth,name,ext] = fileparts(filename);
    switch ext
        case {'','.vtk'}
            ext = '.vtk';
            format = 'legacy-ascii'; % default
        case 'vtp'
            format = 'xml-ascii';
        case {'.vti','.vtr','.vts','.vtu'}
            format = 'xml-ascii';
            warning('Only partially handled.');
        otherwise
            error('Unknown file extension.');
    end
else
    switch lower(format)
        case {'legacy','legacy-ascii','legacy-binary'}
            ext = '.vtk';
        case {'xml','xml-ascii','xml-binary','xml-appended'}
            ext = '.vtp';
        otherwise
            error('Unknown file format.');
    end
end

%-Filename
%--------------------------------------------------------------------------
[pth,name,e] = fileparts(filename);
if ~strcmpi(e,ext)
    warning('Changing file extension from %s to %s.',e,ext);
end
filename = fullfile(pth,[name ext]);

%-Convert input structure if necessary
%--------------------------------------------------------------------------

%-Three scalars per item interpreted as color
% if isfield(M,'cdata') && size(M.cdata,2) == 3
%     M.color = M.cdata;
%     M = rmfield(M,'cdata');
% end

%-Compute normals
if ~isfield(M,'normals')
    M.normals = compute_normals(M);
end

%-Write file
%--------------------------------------------------------------------------
switch lower(format)
    case {'legacy','legacy-ascii'}
        mvtk_write_legacy(M,filename,'ASCII', type);
    case {'legacy-binary'}
        mvtk_write_legacy(M,filename,'BINARY', type);
    case {'xml','xml-ascii'}
        mvtk_write_xml(M,filename,'ASCII');
    case {'xml-binary'}
        mvtk_write_xml(M,filename,'BINARY');
    case {'xml-appended'}
        mvtk_write_xml(M,filename,'APPENDED');
    otherwise
        error('Unknown file format.');
end


%==========================================================================
% function fid = mvtk_write_legacy(s,filename,format)
%==========================================================================
function fid = mvtk_write_legacy(s,filename,format, gtype)

%-Open file
%--------------------------------------------------------------------------
if nargin == 2, format = 'ASCII'; else format = upper(format); end
switch format
    case 'ASCII'
        fopen_opts = {'wt'};
        write_data = @(fid,fmt,prec,dat) fprintf(fid,fmt,dat); 
    case 'BINARY'
        fopen_opts = {'wb','ieee-be'};
        write_data = @(fid,fmt,prec,dat) [fwrite(fid,dat,prec);fprintf(fid,'\n');];
    otherwise
        error('Unknown file format.');
end
fid = fopen(filename,fopen_opts{:});
if fid == -1
    error('Unable to write file %s: permission denied.',filename);
end

%-Legacy VTK file format
%==========================================================================

%- Part 1: file version and identifier
%--------------------------------------------------------------------------
fprintf(fid,'# vtk DataFile Version 2.0\n');

%- Part 2: header
%--------------------------------------------------------------------------
hdr = 'Saved using mVTK';
fprintf(fid,'%s\n',hdr(1:min(length(hdr),256)));

%- Part 3: data type (either ASCII or BINARY)
%--------------------------------------------------------------------------
fprintf(fid,'%s\n',format);

%- Part 4: dataset structure: geometry/topology
%--------------------------------------------------------------------------
% One of: STRUCTURED_POINTS, STRUCTURED_GRID, UNSTRUCTURED_GRID, POLYDATA,
% RECTILINEAR_GRID, FIELD
if isfield(s,'vertices') || isfield(s,'faces')
    type = 'POLYDATA';
elseif isfield(s,'spacing')
    type = 'STRUCTURED_POINTS';
elseif isfield(s,'mat')
   type = 'STRUCTURED_GRID';
else
    error('Unknown dataset structure.');
end
fprintf(fid,'DATASET %s\n',type);
if isfield(s,'vertices')
    fprintf(fid,'POINTS %d %s\n',size(s.vertices,1),'float');
    write_data(fid,'%f %f %f\n','float32',s.vertices');
end
if isfield(s,'faces')
    nFaces = size(s.faces,1);
    nConn = size(s.faces,2);
    fprintf(fid,'POLYGONS %d %d\n',nFaces,nFaces*(nConn+1));
    dat = uint32([repmat(nConn,1,nFaces); (s.faces'-1)]);
    fmt = repmat('%d ',1,size(dat,1)); fmt(end) = '';
    write_data(fid,[fmt '\n'],'uint32',dat);
end
if isfield(s,'spacing')
    fprintf(fid,'DIMENSIONS %d %d %d\n',size(s.cdata));
    fprintf(fid,'ORIGIN %f %f %f\n',s.origin);
    fprintf(fid,'SPACING %f %f %f\n',s.spacing);
    s.cdata = s.cdata(:);
end
% if isfield(s,'mat')
%     dim = size(s.cdata);
%     fprintf(fid,'DIMENSIONS %d %d %d\n',dim);
%     fprintf(fid,'POINTS %d %s\n',prod(dim),'float');
%     [R,C,P]  = ndgrid(1:dim(1),1:dim(2),1:dim(3));
%     RCP      = [R(:)';C(:)';P(:)'];
%     clear R C P
%     RCP(4,:) = 1;
%     XYZmm    = s.mat(1:3,:)*RCP;
%     write_data(fid,'%f %f %f\n','float32',XYZmm);
%     s.cdata = s.cdata(:);
% end
fprintf(fid,'\n');

%- Part 5: dataset attributes (POINT_DATA and CELL_DATA)
%--------------------------------------------------------------------------
point_data_hdr = false;

%-SCALARS (and LOOKUP_TABLE)

if isfield(s,'cdata') && ~isempty(s.cdata)
    if ~point_data_hdr
        fprintf(fid,'POINT_DATA %d\n',size(s.cdata,1));
        point_data_hdr = true;
    end
    fprintf(fid,'COLOR_SCALARS color 3\n');
    %Long Rainbow for scalar Area data
    %Long Rainbow scalar Myelin data
%     s = size(s.cdata)
    if strcmp(gtype, 'bw')
        for i = 1:size(s.cdata)
            m = max(s.cdata(i, :));
            for j = 1:180
                if m == s.cdata(i, j)
                    bwData(i) = (j-1)/180;
                end
            end
    %         y = i
        end
    end
    
    
    no_zeros = s.cdata(s.cdata~=0);
    norm_cdata = (s.cdata - min(no_zeros)) / (max(no_zeros) - min(no_zeros));
    for i = 1:size(s.cdata)
%         x = gtype
        switch(gtype)
            case {'scalar'}
                %outstr = 'building rainbows'
                if s.cdata(i) == 0
                    r = 1;
                    g = 1;
                    b = 1;
                else
                    a = (1-norm_cdata(i))/0.2;
                    x = floor(a);
                    y = (a-x);
                    switch x
                        case 0
                            r = 1;
                            g = y;
                            b = 0;
                        case 1
                            r = 1-y;
                            g = 1;
                            b = 0;
                        case 2
                            r = 0;
                            g = 1;
                            b = y;
                        case 3
                          r = 0;
                          g = 1-y;
                          b = 1;
                        case 4
                            r = y;
                            g = 0;
                            b = 1;
                        case 5
                            r = 1;
                            g = 0;
                            b = 1;
                    end
                end
            case {'label'}
%                 outstr = 'extracting labels'
                %Converting from colour.label.gii
                j = uint32(s.cdata(i));
                if j ~= 0
        %             c = s.labels.rgba(j);
                    r = s.labels.rgba(j+1, 1);
                    g = s.labels.rgba(j+1, 2);
                    b = s.labels.rgba(j+1, 3);
                else
                    r = 0;
                    g = 0;
                    b = 0;
                end
            case {'bw'}
%                 ind = bwData(i)
                if bwData(i) == 0
                    r = 1;
                    g = 1;
                    b = 1;
                else
                    a = (1-bwData(i))/0.2;
                    x = floor(a);
                    y = (a-x);
                    switch x
                        case 0
                            r = 1;
                            g = y;
                            b = 0;
                        case 1
                            r = 1-y;
                            g = 1;
                            b = 0;
                        case 2
                            r = 0;
                            g = 1;
                            b = y;
                        case 3
                          r = 0;
                          g = 1-y;
                          b = 1;
                        case 4
                            r = y;
                            g = 0;
                            b = 1;
                        case 5
                            r = 1;
                            g = 0;
                            b = 1;
                    end
                end
                
        end
        fprintf(fid, '%f %f %f\n', r, g, b);
    end
end

%-SCALAR FIELD FOR BRAIN DISSECTION
% ADD scalar as parcel number
if strcmpi(gtype, 'label')
    strrr = 'adding scalars'
    fprintf(fid,'SCALARS %s %s 1\n','parcelID','float');
    fprintf(fid,'LOOKUP_TABLE default\n');
    foundNums = zeros(1, 181);
    for i = 1:size(s.cdata)
        l = uint32(s.cdata(i));
        if l == 0
            foundNums(181) = foundNums(181) + 1;
        else
            foundNums(l) = foundNums(l) + 1;
        end
        fprintf(fid, '%f\n', l);
    end
    numsFound = foundNums
    total = sum(foundNums)
end
% Add in scalar weights of 1 for the 3d dissection
if strcmpi(gtype, 'label')
    strrr = 'adding scalars'
    fprintf(fid,'SCALARS %s %s 1\n','weight','float');
    fprintf(fid,'LOOKUP_TABLE default\n');
    foundNums = zeros(1, 181);
    for i = 1:size(s.cdata)
        fprintf(fid, '%f\n', 10.0);
    end
end

%-VECTORS
if isfield(s,'vectors') && ~isempty(s.vectors)
    if ~point_data_hdr
        fprintf(fid,'POINT_DATA %d\n',size(s.vectors,1));
        point_data_hdr = true;
    end
    dataName = 'vectors';
    fprintf(fid,'VECTORS %s %s\n',dataName,'float');
    write_data(fid,'%f %f %f\n','float32',s.vectors');
end

%-NORMALS
if isfield(s,'normals') && ~isempty(s.normals)
    if ~point_data_hdr
        fprintf(fid,'POINT_DATA %d\n',size(s.vertices,1));
        point_data_hdr = true;
    end
    dataName = 'normals';
    fprintf(fid,'NORMALS %s %s\n',dataName,'float');
    write_data(fid,'%f %f %f\n','float32',-s.normals');
end

%-TENSORS
if isfield(s,'tensors') && ~isempty(s.tensors)
    if ~point_data_hdr
        fprintf(fid,'POINT_DATA %d\n',size(s.tensors,1));
        point_data_hdr = true;
    end
    dataName = 'tensors';
    fprintf(fid,'TENSORS %s %s\n',dataName,'float');
    write_data(fid,repmat('%f %f %f\n',1,3),'float32',s.tensors');
end

%-Close file
%--------------------------------------------------------------------------
fclose(fid);


%==========================================================================
% function fid = mvtk_write_xml(s,filename,format)
%==========================================================================
function fid = mvtk_write_xml(s,filename,format)

%-Open file
%--------------------------------------------------------------------------
if nargin == 2, format = 'ascii'; else format = lower(format); end
clear store_appended_data
switch format
    case 'ascii'
        fopen_opts = {'wt'};
        write_data = @(fmt,dat) deal(NaN,sprintf(fmt,dat));
    case 'binary'
        fopen_opts = {'wb','ieee-le'};
        write_data = @(fmt,dat) deal(NaN,[...
            base64encode(typecast(uint32(numel(dat)*numel(typecast(dat(1),'uint8'))),'uint8')) ...
            base64encode(typecast(dat(:),'uint8'))]);
    case 'appended'
        fopen_opts = {'wt'};
        store_appended_data('start');
        store_appended_data('base64'); % format: raw, [base64]
        store_appended_data('none'); % compression: none, [zlib]
        write_data = @(fmt,dat) deal(store_appended_data(fmt,dat),'');
    otherwise
        error('Unknown format.');
end
fid = fopen(filename,fopen_opts{:});
if fid == -1
    error('Unable to write file %s: permission denied.',filename);
end

%-XML VTK file format
%==========================================================================
o = @(x) blanks(x*3);

%-XML prolog
%--------------------------------------------------------------------------
fprintf(fid,'<?xml version="1.0"?>\n');

%-VTKFile
%--------------------------------------------------------------------------
VTKFile = struct;
VTKFile.type           = 'PolyData';
VTKFile.version        = '0.1';
VTKFile.byte_order     = 'LittleEndian';
VTKFile.header_type    = 'UInt32';
if strcmp(store_appended_data('compression'),'zlib')
    VTKFile.compressor = 'vtkZLibDataCompressor';
end
fprintf(fid,'<VTKFile');
for i=fieldnames(VTKFile)'
    fprintf(fid,' %s="%s"',i{1},VTKFile.(i{1}));
end
fprintf(fid,'>\n');

%-PolyData
%--------------------------------------------------------------------------
fprintf(fid,'%s<PolyData>\n',o(1));
Piece = struct;
Piece.NumberOfPoints = sprintf('%d',size(s.vertices,1));
Piece.NumberOfVerts  = sprintf('%d',0);
Piece.NumberOfLines  = sprintf('%d',0);
Piece.NumberOfStrips = sprintf('%d',0);
Piece.NumberOfPolys  = sprintf('%d',size(s.faces,1));
fprintf(fid,'%s<Piece',o(2));
for i=fieldnames(Piece)'
    fprintf(fid,' %s="%s"',i{1},Piece.(i{1}));
end
fprintf(fid,'>\n');

%-PointData
%--------------------------------------------------------------------------
PointData = struct;
if isfield(s,'cdata') && ~isempty(s.cdata)
    PointData.Scalars = 'scalars';
end
if isfield(s,'normals') && ~isempty(s.normals)
    PointData.Normals = 'normals';
end
fprintf(fid,'%s<PointData',o(3));
for i=fieldnames(PointData)'
    fprintf(fid,' %s="%s"',i{1},PointData.(i{1}));
end
fprintf(fid,'>\n');

%-Scalars
if isfield(s,'cdata') && ~isempty(s.cdata)
    [offset,dat] = write_data('%f ',single(s.cdata'));
    DataArray = struct;
    DataArray.type = 'Float32';
    DataArray.Name = 'scalars';
    DataArray.NumberOfComponents = sprintf('%d',size(s.cdata,2));
    DataArray.format = format;
    if ~isnan(offset), DataArray.offset = sprintf('%d',offset); end
    fprintf(fid,'%s<DataArray',o(4));
    for i=fieldnames(DataArray)'
        fprintf(fid,' %s="%s"',i{1},DataArray.(i{1}));
    end
    fprintf(fid,'>%s</DataArray>\n',dat);
end

%-Normals
if isfield(s,'normals') && ~isempty(s.normals)
    [offset,dat] = write_data('%f ',single(-s.normals'));
    DataArray = struct;
    DataArray.type = 'Float32';
    DataArray.Name = 'normals';
    DataArray.NumberOfComponents = sprintf('%d',3);
    DataArray.format = format;
    if ~isnan(offset), DataArray.offset = sprintf('%d',offset); end
    fprintf(fid,'%s<DataArray',o(4));
    for i=fieldnames(DataArray)'
        fprintf(fid,' %s="%s"',i{1},DataArray.(i{1}));
    end
    fprintf(fid,'>%s</DataArray>\n',dat);
end

fprintf(fid,'%s</PointData>\n',o(3));

%-CellData
%--------------------------------------------------------------------------
fprintf(fid,'%s<CellData/>\n',o(3));

%-Points
%--------------------------------------------------------------------------
fprintf(fid,'%s<Points>\n',o(3));
if isfield(s,'vertices')
    [offset,dat] = write_data('%f ',single(s.vertices'));
    DataArray = struct;
    DataArray.type = 'Float32';
    DataArray.Name = 'Vertices';
    DataArray.NumberOfComponents = sprintf('%d',3);
    DataArray.format = format;
    if ~isnan(offset), DataArray.offset = sprintf('%d',offset); end
    fprintf(fid,'%s<DataArray',o(4));
    for i=fieldnames(DataArray)'
        fprintf(fid,' %s="%s"',i{1},DataArray.(i{1}));
    end
    fprintf(fid,'>%s</DataArray>\n',dat);
end
fprintf(fid,'%s</Points>\n',o(3));

%-Verts
%--------------------------------------------------------------------------
fprintf(fid,'%s<Verts/>\n',o(3));

%-Lines
%--------------------------------------------------------------------------
fprintf(fid,'%s<Lines/>\n',o(3));

%-Strips
%--------------------------------------------------------------------------
fprintf(fid,'%s<Strips/>\n',o(3));

%-Polys
%--------------------------------------------------------------------------
fprintf(fid,'%s<Polys>\n',o(3));
if isfield(s,'faces')
    [offset,dat] = write_data('%d ',uint32(s.faces'-1));
    DataArray = struct;
    DataArray.type = 'UInt32';
    DataArray.Name = 'connectivity';
    DataArray.format = format;
    if ~isnan(offset), DataArray.offset = sprintf('%d',offset); end
    fprintf(fid,'%s<DataArray',o(4));
    for i=fieldnames(DataArray)'
        fprintf(fid,' %s="%s"',i{1},DataArray.(i{1}));
    end
    fprintf(fid,'>%s</DataArray>\n',dat);
    
    [offset,dat] = write_data('%d ',uint32(3:3:3*size(s.faces,1)));
    DataArray = struct;
    DataArray.type = 'UInt32';
    DataArray.Name = 'offsets';
    DataArray.format = format;
    if ~isnan(offset), DataArray.offset = sprintf('%d',offset); end
    fprintf(fid,'%s<DataArray',o(4));
    for i=fieldnames(DataArray)'
        fprintf(fid,' %s="%s"',i{1},DataArray.(i{1}));
    end
    fprintf(fid,'>%s</DataArray>\n',dat);
end
fprintf(fid,'%s</Polys>\n',o(3));

fprintf(fid,'%s</Piece>\n',o(2));
fprintf(fid,'%s</PolyData>\n',o(1));

%-AppendedData
%--------------------------------------------------------------------------
if strcmp(format,'appended')
    dat = store_appended_data('retrieve');
    store_appended_data('stop');
    AppendedData = struct;
    AppendedData.encoding = store_appended_data('encoding');
    fprintf(fid,'%s<AppendedData',o(1));
    for i=fieldnames(AppendedData)'
        fprintf(fid,' %s="%s"',i{1},AppendedData.(i{1}));
    end
    fprintf(fid,'>\n%s_',o(2));
    fwrite(fid,dat);
    fprintf(fid,'\n%s</AppendedData>\n',o(1));
end

fprintf(fid,'</VTKFile>\n');

%-Close file
%--------------------------------------------------------------------------
fclose(fid);


%==========================================================================
% function varargout = store_appended_data(fmt,dat)
%==========================================================================
function varargout = store_appended_data(fmt,dat)

persistent fid encoding compression

if isempty(encoding), encoding = 'raw'; end
if isempty(compression), compression = 'none'; end
if ~nargin, fmt = 'start'; end
if nargin < 2
    varargout = {};
    switch lower(fmt)
        case 'start'
            filename = tempname;
            fid = fopen(filename,'w+b');
            if fid == -1
                error('Cannot open temporary file.');
            end
        case 'stop'
            filename = fopen(fid);
            fclose(fid);
            delete(filename);
            fid = -1;
        case 'retrieve'
            frewind(fid);
            varargout = {fread(fid)};
        case 'encoding'
            varargout = {encoding};
        case 'compression'
            varargout = {compression};
        case {'raw','base64'}
            encoding = fmt;
        case {'none','zlib'}
            compression = fmt;
        otherwise
            error('Unknown action.');
    end
    return;
end

varargout = {ftell(fid)};
N = uint32(numel(dat)*numel(typecast(dat(1),'uint8')));
switch encoding
    case 'raw'
        switch compression
            case 'none'
                dat = typecast(dat(:),'uint8');
                hdr = N;
            case 'zlib'
                dat = zstream('C',typecast(dat(:),'uint8'));
                hdr = uint32([1 N N numel(dat)]);
            otherwise
                error('Unknown compression.');
        end
        fwrite(fid,hdr,'uint32');
        fwrite(fid,dat,class(dat));
    case 'base64'
        switch compression
            case 'none'
                dat = typecast(dat(:),'uint8');
                hdr = N;
            case 'zlib'
                dat = zstream('C',typecast(dat(:),'uint8'));
                hdr = uint32([1 N N numel(dat)]);
            otherwise
                error('Unknown compression.');
        end
        fwrite(fid,base64encode(typecast(hdr,'uint8')));
        fwrite(fid,base64encode(dat));
    otherwise
        error('Unknown encoding.');
end


%==========================================================================
% function N = compute_normals(S)
%==========================================================================
function N = compute_normals(S)
try
    t = triangulation(double(S.faces),double(S.vertices));
    N = -double(t.vertexNormal);
    normN = sqrt(sum(N.^2,2));
    normN(normN < eps) = 1;
    N = N ./ repmat(normN,1,3);
catch
    N = [];
end
