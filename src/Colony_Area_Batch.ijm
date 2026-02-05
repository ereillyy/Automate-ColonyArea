// Macro to open images from an input folder and run colony area plugin on each image present, recording all results by id of the filename.

// Instructions for user
showMessage("Colony Area Batch Processing", "Please select a directory containing ALL the images for analysis.");

// Get input folder from user
inputDir = getDirectory("Choose input folder with images");

// Get rectangle coordinates from user
Dialog.create("Rectangle Selection");
Dialog.addString("Rectangle (x, y, width, height):", "248, 280, 3552, 5464", 30);
Dialog.addChoice("Plate format:", newArray("6-well", "12-well", "24-well"), "6-well");
Dialog.show();
rectString = Dialog.getString();
plateFormat = Dialog.getChoice();

// Parse rectangle coordinates
rectParts = split(rectString, ",");
rectX = parseInt(rectParts[0]);
rectY = parseInt(rectParts[1]);
rectWidth = parseInt(rectParts[2]);
rectHeight = parseInt(rectParts[3]);

// Set plate parameters based on format
if (plateFormat == "6-well") {
    plateNum = 1;
    plateCols = 2;
    plateRows = 3;
} else if (plateFormat == "12-well") {
    plateNum = 2;
    plateCols = 3;
    plateRows = 4;
} else if (plateFormat == "24-well") {
    plateNum = 3;
    plateCols = 4;
    plateRows = 6;
}

// Remove trailing slash from inputDir if present
if (endsWith(inputDir, "/")) {
    inputDir = substring(inputDir, 0, lengthOf(inputDir) - 1);
}

// Get file list
fileList = getFileList(inputDir);

// Build array of image files
imageFiles = newArray(fileList.length);
imageCount = 0;
imageList = "";
for (i = 0; i < fileList.length; i++) {
    filename = fileList[i];
    if (!endsWith(filename, "/") && 
        (endsWith(filename, ".jpg") || endsWith(filename, ".jpeg") || 
         endsWith(filename, ".png") || endsWith(filename, ".tif") || 
         endsWith(filename, ".tiff") || endsWith(filename, ".JPG") || 
         endsWith(filename, ".JPEG") || endsWith(filename, ".PNG") || 
         endsWith(filename, ".TIF") || endsWith(filename, ".TIFF"))) {
        imageFiles[imageCount] = filename;
        imageCount++;
        imageList = imageList + "  " + imageCount + ". " + filename + "\n";
    }
}

if (imageCount == 0) {
    showMessage("Error", "No image files found in the selected directory!");
    exit();
}

// Trim array to actual size
imageFiles = Array.trim(imageFiles, imageCount);

print("=== Found " + imageCount + " image(s) to process ===");
print(imageList);

// Show preview of rectangle on first image
open(inputDir + "/" + imageFiles[0]);
makeRectangle(rectX, rectY, rectWidth, rectHeight);
setTool("rectangle");

// Allow user to adjust rectangle
waitForUser("Adjust Rectangle", "Adjust the rectangle selection if needed.\nRectangle should touch other edges of outer wells as closely as possible.\nClick OK to proceed with processing.");

// Get the (potentially adjusted) rectangle coordinates
getSelectionBounds(rectX, rectY, rectWidth, rectHeight);

// Close preview
close();

// Could add feature here to allow user to check through all images and adjust rectangle per image if necessary. Check if any demand before implementing

// Run in batch mode to avoid user interaction
setBatchMode(true);

// Create output directory
tmpDir = inputDir + "/tmp/";
File.makeDirectory(tmpDir);
print("Segmentation and thresholding directory: " + tmpDir);

// Track failed images
failedImages = newArray(imageFiles.length);
failedCount = 0;

// Process each image file
for (i = 0; i < imageFiles.length; i++) {
    filename = imageFiles[i];
    print(filename);
    
    // Delete any existing wells file to ensure fresh processing
    wellsFilePath = tmpDir + "wells_" + filename + ".tif";
    if (File.exists(wellsFilePath)) {
        File.delete(wellsFilePath);
    }
    
    // Open the image
    open(inputDir + "/" + filename);
    print("Opened: " + filename);
    // Make rectangle selection
    makeRectangle(rectX, rectY, rectWidth, rectHeight);
    print("Made rectangle selection");
    
    // Temporarily exit batch mode for Colony area to work properly
    setBatchMode(false);
    
    // Run Colony area plugin with batch parameters
    run("Colony area", "save=" + tmpDir + " plate=" + plateNum + " cols=" + plateCols + " rows=" + plateRows);
    
    // Check if wells file was created (indicates success)
    if (!File.exists(wellsFilePath)) {
        print("FAILED: " + filename + " - no wells file created (likely geometry validation error)");
        failedImages[failedCount] = filename;
        failedCount++;
    } else {
        print("SUCCESS: " + filename);
    }
    
    // Re-enable batch mode
    setBatchMode(true);
    
    // Close any remaining images
    while (nImages > 0) {
        selectImage(nImages);
        close();
    }
    print("Closed: " + filename);
}

// Report failures
if (failedCount > 0) {
    print("\n=== FAILED IMAGES (" + failedCount + " of " + imageFiles.length + ") ===");
    print("The following images failed geometry validation:");
    for (i = 0; i < failedCount; i++) {
        print("  - " + failedImages[i]);
    }
    print("Check the log above for specific geometry error messages (horizontal/vertical mismatch).");
    print("You may need to adjust the rectangle selection or check image alignment.");
}

print("\n=== Step 2: Running Manual Thresholding ===");

// Get list of wells files
wellsFiles = getFileList(tmpDir);

// Find first wells file for threshold preview
firstWellsFile = "";
for (i = 0; i < wellsFiles.length; i++) {
    if (startsWith(wellsFiles[i], "wells_") && endsWith(wellsFiles[i], ".tif")) {
        firstWellsFile = wellsFiles[i];
        break;
    }
}

if (firstWellsFile == "") {
    showMessage("Error", "No wells files found! Colony area processing may have failed.");
    exit();
}

// Threshold preview loop
thresholdAccepted = false;
manualThreshold = 200;

while (!thresholdAccepted) {
    // Get manual threshold value from user
    manualThreshold = getNumber("Enter manual threshold value:\n(can be adjusted later)", manualThreshold);
    
    // Open first wells file for preview + store name of this origonal window for later
    open(tmpDir + firstWellsFile);
    previewTitle = getTitle();
    
    // Ensure 8-bit
    run("8-bit");
    
    // Duplicate first slice (well) of first wells file for preview
    setSlice(1);
    run("Duplicate...", "title=Preview_Intensity");
    selectWindow(previewTitle);
    run("Duplicate...", "title=Preview_Mask");
    
    // Create mask preview
    selectWindow("Preview_Mask");
    setThreshold(1, manualThreshold);
    run("Convert to Mask");
    
    // Process intensity preview
    selectWindow("Preview_Intensity");
    run("Invert");
    
    // Combine
    imageCalculator("AND", "Preview_Intensity", "Preview_Mask");
    
    // Apply Fire LUT (mimic manual thresholder)
    selectWindow("Preview_Intensity");
    run("Fire");
    run("Invert LUT");
    
    // Clean up mask
    selectWindow("Preview_Mask");
    close();
    
    // Arrange windows side by side for comparison
    selectWindow(previewTitle);
    setSlice(1);
    setBatchMode("show");
    selectWindow("Preview_Intensity");
    setBatchMode("show");
    
    // Tile windows horizontally for side-by-side comparison using built-in ImageJ command
    run("Tile");
    
    thresholdAccepted = getBoolean("Preview of threshold " + manualThreshold + " on first well.\nProceed with this threshold?", "Proceed", "Try Different Threshold");
    
    // Close both preview windows
    selectWindow(previewTitle);
    close();
    selectWindow("Preview_Intensity");
    close();
    setBatchMode(true);
}

print("Using manual threshold: " + manualThreshold);

// Process all wells files with the chosen threshold
for (i = 0; i < wellsFiles.length; i++) {
    wellsFilename = wellsFiles[i];
    
    // Only process wells_*.tif files
    if (startsWith(wellsFilename, "wells_") && endsWith(wellsFilename, ".tif")) {
        print("\n--- Processing: " + wellsFilename + " ---");
        
        // Open the wells file and store name of this window for later
        open(tmpDir + wellsFilename);
        originalTitle = getTitle();
        print("Opened: " + originalTitle);
        
        // Ensure 8-bit
        run("8-bit");
        
        numSlices = nSlices;
        print("Number of wells: " + numSlices);
        
        // Process each slice like Manual_colony_thresholder does
        for (slice = 1; slice <= numSlices; slice++) {
            selectWindow(originalTitle);
            setSlice(slice);
            print("  Processing well " + slice + "/" + numSlices);
            
            // Duplicate this slice twice - one for mask, one for intensity
            run("Duplicate...", "title=Masked_Well_" + slice);
            selectWindow(originalTitle);
            run("Duplicate...", "title=I_Well_" + slice);
            
            // Create mask
            selectWindow("Masked_Well_" + slice);
            setThreshold(1, manualThreshold);
            run("Convert to Mask");
            
            // Process intensity image (like original: invert)
            selectWindow("I_Well_" + slice);
            run("Invert");
            
            // Combine: AND keeps intensities but applies mask
            imageCalculator("AND", "I_Well_" + slice, "Masked_Well_" + slice);
            
            // Clean up mask (keep intensity for now to save...)
            selectWindow("Masked_Well_" + slice);
            close();
        }
        
        // Close original
        selectWindow(originalTitle);
        close();
        
        // Stack all the intensity (I_Well) images
        run("Images to Stack", "name=thresholded_" + wellsFilename + " title=I_Well");
        
        // Apply Fire LUT and invert
        run("Fire");
        run("Invert LUT");
        
        // Save
        saveAs("Tiff", tmpDir + "thresholded_" + wellsFilename);
        print("Saved: " + tmpDir + "thresholded_" + wellsFilename);
        
        // Close
        close();
    }
}

print("\n=== Step 3: Running Colony Measurer ===");

// Create combined results file
resultsPath = inputDir + "/Colony_area_batch_results.tsv";
resultsFile = File.open(resultsPath);

// Write header
print(resultsFile, "Original Image\tWell #\tArea Percent\tIntensity Percent");

// Build array of thresholded wells files
allFiles = getFileList(tmpDir);
thresholdedFiles = newArray(allFiles.length);
thresholdedCount = 0;
for (i = 0; i < allFiles.length; i++) {
    if (startsWith(allFiles[i], "thresholded_wells_") && endsWith(allFiles[i], ".tif")) {
        thresholdedFiles[thresholdedCount] = allFiles[i];
        thresholdedCount++;
    }
}
thresholdedFiles = Array.trim(thresholdedFiles, thresholdedCount);

for (i = 0; i < thresholdedFiles.length; i++) {
    thresholdedFilename = thresholdedFiles[i];
    print("\n--- Measuring: " + thresholdedFilename + " ---");
        
        // Extract original image name from filename
        // thresholded_wells_CPT_2.5.tif -> CPT_2.5
        originalName = replace(thresholdedFilename, "thresholded_wells_", "");
        originalName = replace(originalName, ".tif", "");
        
        // Open the thresholded wells file
        open(tmpDir + thresholdedFilename);
        imageTitle = getTitle();
        
        // Get image dimensions
        height = getHeight();
        width = getWidth();
        numSlices = nSlices;
        
        // Set measurements
        run("Set Measurements...", "area mean area_fraction redirect=None decimal=1");
        
        // Calculate ratio for circular well correction (same as Colony_measurer)
        in = 0;
        total = height * width;
        for (x = 0; x < height; x++) {
            for (y = 0; y < width; y++) {
                if ((x - height/2) * (x - height/2) * width * width / 4 + 
                    (y - width/2) * (y - width/2) * height * height / 4 <= 
                    (height * height * width * width / 16)) {
                    in = in + 1;
                }
            }
        }
        ratio = in / total;
        
        // Measure each slice (well)
        for (slice = 1; slice <= numSlices; slice++) {
            setSlice(slice);
            run("Measure");
            
            // Get measurements
            areafrac = getResult("%Area");
            area = getResult("Area");
            mean = getResult("Mean");
            
            // Apply circular well correction
            areafrac = areafrac / ratio;
            
            // Calculate intensity fraction
            sumofi = area * mean;
            maxsumofi = area * 255 * ratio;
            intensityfrac = sumofi * 100 / maxsumofi;
            
            // Write to combined results file
            print(resultsFile, originalName + "\t" + slice + "\t" + 
                  d2s(areafrac, 2) + "\t" + d2s(intensityfrac, 2));
            
            print("  Well " + slice + ": Area=" + d2s(areafrac, 2) + "%, Intensity=" + d2s(intensityfrac, 2) + "%");
        }
        
        // Clear results table for next image
        run("Clear Results");
        
        // Close image
        close();
}

// Close results file
File.close(resultsFile);
print("\nCombined results saved to: " + resultsPath);

// Close Results window if open
if (isOpen("Results")) {
    selectWindow("Results");
    run("Close");
}

// Open combined results file
open(resultsPath);

print("\n=== Processing Complete ===");

// Show completion message
showMessage("All Done!", "All done! Please check on the well segmentation and thresholding.\nOpening tmp/ directory...");

// Open tmp directory (cross-platform)
osName = getInfo("os.name");
if (indexOf(osName, "Mac") >= 0) {
    exec("open", tmpDir);
} else if (indexOf(osName, "Windows") >= 0) {
    exec("explorer", tmpDir);
} else {
    // Linux
    exec("xdg-open", tmpDir);
}



// Here is the recorder of manual image processing --> aim to batch this
//run("Select path", "inputfile=/path/to/data/example1/CPT_2.5.jpg");
//selectImage("CPT_2.5.jpg");
//makeRectangle(248, 280, 3552, 5464);
//run("Colony area", "save=/path/to/data/CPT_2.5.jpg input=1 enter=2 enter=3");
//setOption("ScaleConversions", true);
//selectImage("thresholded_wells_CPT_2.5.tif");
//close;
//run("Manual colony thresholder");
//setOption("ScaleConversions", true);
//selectImage("thresholded_wells_CPT_2.5_1.tif");
//run("Colony measurer");