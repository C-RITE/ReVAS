function [refFrame] = MakeMontage(params, fileName)
% MakeMontage    Reference frame.
%   MakeMontage(params, fileName) generates a reference frame by averaging
%   all the pixel values across all frames in a video.
%   
%   Note: The params variable should have the attributes params.stripHeight,
%   params.positions, and params.time.
%   params.newStripHeight is an optional parameter.
%
%   Example: 
%       params.stripHeight = 15;
%       params.time = 1/540:1/540:1;
%       params.positions = randn(540, 2);
%       MakeMontage(params,'fileName');

%% Prepare a new field for newStripHeight
% newStripHeight will give the requisite information for interpolation
% between the spaced-out strips later.
if isfield(params, 'newStripHeight')
    % if params.newStripHeight is a field but no value is specified, then set
    % params.newStripHeight equal to params.stripHeight
    if isempty(params.newStripHeight)
        params.newStripHeight = params.stripHeight;
    end
    
    % if params.newStripHeight is not a field, set params.newStripHeight
    % equal to params.stripHeight anyway
else
    params.newStripHeight = params.stripHeight;
end

%% Set up all variables
stripIndices = params.positions;
t1 = params.time;

% grabbing info about the video and strips
videoInfo = VideoReader(fileName);
frameHeight = videoInfo.Height;
width = videoInfo.Width;
frameRate = videoInfo.Framerate;
totalFrames = frameRate * videoInfo.Duration;
stripsPerFrame = round(frameHeight/params.newStripHeight);

% setting up templates for reference frame and counter array
counterArray = zeros(frameHeight*2);
refFrame = zeros(frameHeight*2);

% Negate all positions. stripIndices tells how far a strip has moved from
% the reference--therefore, to compensate for that movement, the
% stripIndices have to be negated when placing the strip on the template
% frame.
stripIndices = -stripIndices;

%% Set up the interpolation
% scaling the time array to accomodate new strip height
scalingFactor = ((params.stripHeight)/2)/(totalFrames*frameHeight);
t1 = t1 + scalingFactor;
dt = params.newStripHeight / (totalFrames * frameHeight);
t2 = dt:dt:videoInfo.Duration + scalingFactor;

% Make sure that both time arrays have the same dimensions
if size(t2, 1) ~= size(t1, 1) && size(t2, 2) ~= size(t1, 2)
    t2 = t2';
end

%% Remove NaNs in stripIndices
% First handle the case in which NaNs are at the beginning of stripIndices
NaNIndices = find(isnan(stripIndices));
if ~isempty(NaNIndices)
    if NaNIndices(1) == 1
        numberOfNaNs = 1;
        index = 1;
        while index <= size(NaNIndices, 1)
            if NaNIndices(index + 1) == NaNIndices(index) + 1
                numberOfNaNs = numberOfNaNs + 1;
            end
            index = index + 1;
        end
        stripIndices(1:numberOfNaNs) = [];
        t1(1:numberOfNaNs) = [];
    end
end

% Then replace the rest of the NaNs with linear interpolation, done
% manually in a helper function. NaNs at the end of stripIndices will be
% deleted, along with their corresponding time points.
[filteredStripIndices1, lengthCutOut1] = FilterStrips(stripIndices(:, 1));
[filteredStripIndices2, lengthCutOut2] = FilterStrips(stripIndices(:, 2));
filteredStripIndices = [filteredStripIndices1 filteredStripIndices2];
t1(end-max(lengthCutOut1, lengthCutOut2)+1:end) = [];

%% Perform interpolation with finer time interval

% interpolating positions between strips
interpolatedPositions = interp1(t1, filteredStripIndices, t2, 'linear');
interpolatedPositions = movmean(interpolatedPositions, 45);

%% Prepare interpolatedPositions for generating the reference frame.

% Add a third column to interpolatedPositions to hold the strip numbers
% because when I filter for NaNs, the strip number method I originally used
% gets thrown off.
for k = 1:size(interpolatedPositions, 1)
    interpolatedPositions(k, 3) = k;
end

% Remove leftover NaNs. Need to use while statement because the size of
% interpolatedPositions changes each time I remove an NaN
k = 1;
while k<=size(interpolatedPositions, 1)
    if isnan(interpolatedPositions(k, 2))
        interpolatedPositions(k, :) = [];
        t2(k) = [];
        continue
    end
    k = k + 1;
end

% Scale the strip coordinates so that all values are positive. Take the
% negative value with the highest magnitude in each column of
% framePositions and add that value to all the values in the column. This
% will zero the most negative value (like taring a weight scale). Then add
% a positive integer to make sure all values are > 0 (i.e., if we leave the
% zero'd value in framePositions, there will be indexing problems later,
% since MatLab indexing starts from 1 not 0).
column1 = interpolatedPositions(:, 1);
column2 = interpolatedPositions(:, 2); 
if column1(column1<=0)
    if column1(column1<0)
        mostNegative = max(-1*column1);
    else
        mostNegative = 0;
    end
    interpolatedPositions(:, 1) = interpolatedPositions(:, 1) + mostNegative + 2;
end

if column2(column2<=0)
    if column2(column2<0)
        mostNegative = max(-1*column2);
    else
        mostNegative = 0;
    end
    interpolatedPositions(:, 2) = interpolatedPositions(:, 2) + mostNegative + 2;
end

if column1(column1<0.5)
    interpolatedPositions(:, 1) = interpolatedPositions(:,1) + 2;
end

if column2(column2<0.5)
    interpolatedPositions(:, 2) = interpolatedPositions(:, 2) + 2;
end

% Round the final scaled positions to get valid matrix indices
interpolatedPositions = round(interpolatedPositions);

%% Use interpolatedPositions to generate the reference frame.

for frameNumber = 1:totalFrames 
    % Read frame and convert pixel values to signed integers
    videoFrame = double(readFrame(videoInfo))/255;

    % get the appropriate strips from stripIndices for each frame
    startFrameStrips = round(1 + ((frameNumber-1)*(stripsPerFrame)));
    endFrameStrips = round(frameNumber * stripsPerFrame);
    frameStripsWithoutNaN = zeros(size(startFrameStrips:endFrameStrips, 2), 3);
    
    % Extract the strip positions that will be used from this frame. Some
    % strips may be missing because NaNs were removed earlier
    for k = 1:size(interpolatedPositions, 1)
        if startFrameStrips <= interpolatedPositions(k, 3) && ...
                interpolatedPositions(k, 3) <= endFrameStrips
            frameStripsWithoutNaN(k, :) = interpolatedPositions(k, :);
        end
    end

    % Remove extra 0's from frameStripsWithoutNaN, leftover from the
    % preallocation.
    k = 1;
    while k<=size(frameStripsWithoutNaN, 1)
        if frameStripsWithoutNaN(k, :) == 0
            frameStripsWithoutNaN(k, :) = [];
            continue
        end
        k = k + 1;
    end

    for strip = 1 : size(frameStripsWithoutNaN, 1)
        
        % Keep track of the stripNumber so we can shift it accordingly
        stripNumber = mod(frameStripsWithoutNaN(strip, 3), stripsPerFrame);
        if stripNumber == 0
            % For example, if there are 30 strips per frame and this is the
            % 30th strip, the mod function will say this is the 0th strip
            % when really it is the 30th strip
            stripNumber = stripsPerFrame;
        end
        
        % row and column "coordinates" of the top left pixel of each strip
        topLeft = [frameStripsWithoutNaN(strip, 1), frameStripsWithoutNaN(strip, 2)];
        rowIndex = topLeft(2);
        columnIndex = topLeft(1);
        
        % move strip to proper position
        rowIndex = rowIndex + ((stripNumber-1) * params.newStripHeight);

        % get max row/column of the strip
        maxRow = rowIndex + params.newStripHeight - 1;
        maxColumn = columnIndex + width - 1;
        
        % transfer values of the strip pixels to the reference frame, and
        % increment the corresponding location on the counter array
        templateSelectRow = rowIndex:maxRow;
        templateSelectColumn = columnIndex:maxColumn;
        vidStart = ((stripNumber-1)*params.newStripHeight)+1;
        vidEnd = stripNumber * params.newStripHeight;
        
        % If the strip extends beyond the frame (i.e., the frame has a
        % height of 512 pixels and strip of height 10 begins at row 511)
        % set the max row of that strip to be the last row of the frame.
        % Also make templateSelectRow smaller to match the dimensions of
        % the new strip
         if vidEnd > size(videoFrame, 1)
             difference = vidEnd - size(videoFrame, 1);
             vidEnd = size(videoFrame, 1);
             templateSelectRow = rowIndex:(maxRow-difference);
         end
        
        templateSelectRow = round(templateSelectRow);
        templateSelectColumn = round(templateSelectColumn);
        vidStart = round(vidStart);
        vidEnd = round(vidEnd);
       
        refFrame(templateSelectRow, templateSelectColumn) = refFrame(...
            templateSelectRow, templateSelectColumn) + videoFrame(...
            vidStart:vidEnd, :);
        counterArray(templateSelectRow, templateSelectColumn) = counterArray...
            (templateSelectRow, templateSelectColumn) + 1;
    end
end

% divide each pixel in refFrame by the number of strips that contain that pixel
refFrame = refFrame./counterArray;

%% Take care of miscellaneous issues from preallocation and division by 0.

% Crop out the leftover 0 padding from the original template.
column1 = interpolatedPositions(:, 1);
column2 = interpolatedPositions(:, 2);
minColumn = min(column1);
minRow = min(column2);
maxColumn = max(column1);
refFrame(1:floor((minRow-1)), :) = [];
refFrame(:, 1:floor((minColumn-1))) = [];
refFrame(:, ceil(maxColumn+width):end) = [];

% Convert any NaN values in the reference frame to a 0. Otherwise, running
% strip analysis on this new frame will not work
NaNindices = find(isnan(refFrame));
for k = 1:size(NaNindices)
    NaNindex = NaNindices(k);
    refFrame(NaNindex) = 0;
end

% Need to take care of rows separately for cropping out 0 padding because 
% strip locations do not give info about where the template frame ends,
% only where that strip is located relative to the corresponding strip on
% the original reference frame.
k = 1;
while k<=size(refFrame, 1)
    if refFrame(k, :) == 0
        refFrame(k, :) = [];
        continue
    end
    k = k + 1;
end

%% Save and display the reference frame.
save('Reference Frame', 'refFrame');
figure('Name', 'Reference Frame')
imshow(refFrame);

end