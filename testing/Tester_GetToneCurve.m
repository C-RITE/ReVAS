function success = Tester_GetToneCurve

% suppress warnings
origState = warning;
warning('off','all');

try 
    %% load image
    im = imread('cameraman.tif');
    
    %% First test
    % with default params
    [~, toneMapper] = GetToneCurve;

    % try applying to image
    imMapped = toneMapper(im);

    %% Second test
    [~, toneMapper2] = GetToneCurve(31, 1.6, 170);
    imMapped2 = toneMapper2(im);
    
    figure(2020);
    cla;
    montage({im,imMapped,imMapped2},'size',[1,3]);

    %% Third test
    x = linspace(0,1,256);
    gammaCurve = x.^0.6;
    toneCurve = GetToneCurve(x*255, gammaCurve./x, 255);

    assert(all(uint8(255*toneCurve) == uint8(255*gammaCurve')));

    success = true;
catch
    success = false;

end


warning(origState);