function [outputVideo, params] = GammaCorrect(inputVideo, params)
%GAMMA CORRECT Applies gamma correction or some other contrast enhancement
% operation to the video.
%
%   -----------------------------------
%   Input
%   -----------------------------------
%   |inputVideo| is either the path to the video, or the video matrix itself. 
%   In the former situation, the result is written with '_gamscaled' appended to the
%   input file name. In the latter situation, no video is written and
%   the result is returned.
%
%   |params| is a struct as specified below.
%
%   Fields of the |params| 
%   -----------------------------------
%   overwrite          : set to true to overwrite existing files.
%                        Set to false to params.abort the function call if the
%                        files already exist. (default false)
%   enableVerbosity    : true/false. plots first frame after gamma
%                        correction.
%   method             : 'simpleGamma' for simple gamma correction, 
%                        'toneMapping' for boosting only low-mid grays, 
%                        'histEq' for histogram equalization. (default
%                        'simpleGamma'). Only one of the methods can be
%                        applied with a single call to this function.
%   gammaExponent      : (applies only when 'simpleGamma' method is 
%                        selected) gamma specifies the shape of the curve 
%                        describing the relationship between the 
%                        values in I and J, where new intensity
%                        values are being mapped from I (a frame) 
%                        to J. gammaExponent is a scalar value.
%                        (default 0.6)
%   toneCurve          : a 256x1 uint8 array for mapping pixel values to
%                        new values by simply indexing toneCurve using
%                        video frame itself. 
%   histLevels         : number of levels to be used in histeq. (default 64)
%   badFrames          : specifies blink/bad frames. we can skip those but
%                        we need to make sure to keep a record of 
%                        discarded frames. 
%   axesHandles        : handles to an axes object.
%
%
%   -----------------------------------
%   Output
%   -----------------------------------
%   |outputVideo| is path to new video if 'inputVideo' is also a path. If
%   'inputVideo' is a 3D array, |outputVideo| is also a 3D array.
%
%   |params| structure
%
%   Example usage: 
%       inputVideo = 'tslo-dark.avi';
%       params.overwrite = true;
%       params.method = 'simpleGamma';
%       params.gammaExponent = 0.6;
%       GammaCorrect(inputVideo, params);



%% Determine inputVideo type.
if ischar(inputVideo)
    % A path was passed in.
    % Read the video and once finished with this module, write the result.
    writeResult = true;
else
    % A video matrix was passed in.
    % Do not write the result; return it instead.
    writeResult = false;
end

%% Set parameters to defaults if not specified.

if nargin < 2
    params = struct;
end

% validate params
[~,callerStr] = fileparts(mfilename);
[default, validate] = GetDefaults(callerStr);
params = ValidateField(params,default,validate,callerStr);


%% Handle GUI mode
% params can have a field called 'logBox' to show messages/warnings 
if isfield(params,'logBox')
    logBox = params.logBox;
    isGUI = true;
else
    logBox = [];
    isGUI = false;
end

% params will have access to a uicontrol object in GUI mode. so if it does
% not already have that, create the field and set it to false so that this
% module can be used without the GUI
if ~isfield(params,'abort')
    params.abort.Value = false;
end

%% Handle verbosity 
if ischar(params.enableVerbosity)
    params.enableVerbosity = find(contains({'none','video','frame'},params.enableVerbosity))-1;
end

% check if axes handles are provided, if not, create axes.
if params.enableVerbosity && isempty(params.axesHandles)
    fh = figure(2020);
    set(fh,'name','Gamma Correction',...
           'units','normalized',...
           'outerposition',[0.16 0.053 0.4 0.51],...
           'menubar','none',...
           'toolbar','none',...
           'numbertitle','off');
    params.axesHandles(1) = subplot(1,1,1);
end

if params.enableVerbosity
    cla(params.axesHandles(1))
    tb = get(params.axesHandles(1),'toolbar');
    tb.Visible = 'on';
end


%% Handle overwrite scenarios.
if writeResult
    outputVideoPath = Filename(inputVideo, 'gamma');
    params.outputVideoPath = outputVideoPath;
    
    if ~exist(outputVideoPath, 'file')
        % left blank to continue without issuing warning in this case
    elseif ~params.overwrite
        RevasWarning(['GammaCorrect() did not execute because it would overwrite existing file. (' outputVideoPath ')'], logBox);
        return;
    else
        RevasWarning(['GammaCorrect() is proceeding and overwriting an existing file. (' outputVideoPath ')'], logBox);
    end
end


%% Create reader/writer objects and get some info on videos

if writeResult
    writer = VideoWriter(outputVideoPath, 'Grayscale AVI');
    reader = VideoReader(inputVideo);
    % some videos are not 30fps, we need to keep the same framerate as
    % the source video.
    writer.FrameRate=reader.Framerate;
    open(writer);

    % Determine dimensions of video.
    numberOfFrames = reader.Framerate * reader.Duration;
else
    % Determine dimensions of video.
    [height, width, numberOfFrames] = size(inputVideo);
    
    % preallocate the output video array
    outputVideo = zeros(height, width, numberOfFrames-sum(params.badFrames),'uint8');

end

%% badFrames handling
params = HandleBadFrames(numberOfFrames, params, callerStr);


%% Contrast enhancement

if strcmpi(params.method,'simpleGamma')
    simpleGammaToneCurve = uint8((linspace(0,1,256).^params.gammaExponent)*255);
end

% Read, do contrast enhancement, and write frame by frame.
for fr = 1:numberOfFrames
    if ~params.abort.Value

        % get next frame
        if writeResult
            frame = readFrame(reader);
            if ndims(frame) == 3
                frame = rgb2gray(frame);
            end
        else
            frame = inputVideo(:,:, fr);
        end

        % if it's a blink frame, skip it.
        if params.skipFrame(fr)
            continue;
        end

        % apple contrast enhancement here
        switch params.method
            case 'simpleGamma'
                newFrame = simpleGammaToneCurve(frame+1);
                
            case 'toneMapping'
                newFrame = params.toneCurve(frame+1);
                
            case 'histEq'
                newFrame = uint8(histeq(frame, params.histLevels));
                
            otherwise
                error('unknown method type for contrast GammaCorrect().');
        end

        % visualize
        if (params.enableVerbosity == 1 && fr == 1) || params.enableVerbosity > 1
            axes(params.axesHandles(1)); %#ok<LAXES>
            if fr == 1
                imh = imshow([frame uint8(255*ones(size(frame,1),10)) newFrame],'border','tight');
            else
                imh.CData = [frame uint8(255*ones(size(frame,1),10)) newFrame];
            end
            title(params.axesHandles(1),sprintf('Gamma correcting. %d out of %d',fr, numberOfFrames))
        end

        % write out
        if writeResult
            writeVideo(writer, newFrame);
        else
            nextFrameNumber = sum(~params.badFrames(1:fr));
            outputVideo(:, :, nextFrameNumber) = newFrame; 
        end
    else
        break;
    end % abort
    
    if isGUI
        pause(.02);
    end
end % end of video

%% return results, close up objects

if writeResult 
    outputVideo = outputVideoPath;
    
    close(writer);
    
    % if aborted midway through video, delete the partial video.
    if params.abort.Value
        delete(outputVideoPath)
    end
end

% remove unnecessary fields
params = RemoveFields(params,{'logBox','axesHandles','abort'}); 

