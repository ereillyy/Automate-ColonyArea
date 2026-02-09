// Macro to test multiple threshold values and analyse their effect on colony area and intensity measurements

// Instructions
showMessage("Colony Threshold Test", "Select one or more plate images to analyse.\nThis will test thresholds from 50-250 to help you choose the optimal value.");

// Get image files from user
imageFiles = newArray(0);
selectMore = true;

while (selectMore) {
    path = File.openDialog("Select plate image(s) - click Cancel when done");
    if (path != "") {
        imageFiles = Array.concat(imageFiles, path);
        selectMore = getBoolean("Image added: " + File.getName(path) + "\n\nAdd another image?", "Add More", "Done");
    } else {
        selectMore = false;
    }
}

if (imageFiles.length == 0) {
    showMessage("Error", "No images selected!");
    exit();
}

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
    totalWells = 6;
} else if (plateFormat == "12-well") {
    plateNum = 2;
    plateCols = 3;
    plateRows = 4;
    totalWells = 12;
} else if (plateFormat == "24-well") {
    plateNum = 3;
    plateCols = 4;
    plateRows = 6;
    totalWells = 24;
}

// Show preview on first image
open(imageFiles[0]);
makeRectangle(rectX, rectY, rectWidth, rectHeight);
setTool("rectangle");
waitForUser("Adjust Rectangle", "Adjust the rectangle if needed.\nClick OK to proceed.");
getSelectionBounds(rectX, rectY, rectWidth, rectHeight);
close();

// Ask which wells to analyse for each image
wellSelectionsPerImage = newArray(imageFiles.length);

for (imgIdx = 0; imgIdx < imageFiles.length; imgIdx++) {
    imageName = File.getName(imageFiles[imgIdx]);
    Dialog.create("Well Selection: " + imageName);
    Dialog.addMessage("Select wells to analyse for: " + imageName);
    Dialog.addString("Wells (e.g., 'all', '1', '1,3,5', or '1-6'):", "all", 20);
    Dialog.show();
    wellSelectionsPerImage[imgIdx] = Dialog.getString();
}

print("\\Clear");
print("=== Colony Threshold Test ===");
print("Images: " + imageFiles.length);
for (imgIdx = 0; imgIdx < imageFiles.length; imgIdx++) {
    print("  " + File.getName(imageFiles[imgIdx]) + " -> Wells: " + wellSelectionsPerImage[imgIdx]);
}
print("Threshold range: 50-250 (step 5)");

// Function to parse well selection string into array of well numbers
function parseWellSelection(selectionStr, maxWells) {
    selectionStr = toLowerCase(trim(selectionStr));
    wells = newArray(0);
    
    if (selectionStr == "all") {
        for (w = 1; w <= maxWells; w++) {
            wells = Array.concat(wells, w);
        }
        return wells;
    }
    
    // Split by comma
    parts = split(selectionStr, ",");
    for (p = 0; p < parts.length; p++) {
        part = trim(parts[p]);
        
        // Check if it's a range (e.g., "1-6")
        if (indexOf(part, "-") >= 0) {
            rangeParts = split(part, "-");
            start = parseInt(trim(rangeParts[0]));
            end = parseInt(trim(rangeParts[1]));
            for (w = start; w <= end; w++) {
                if (w >= 1 && w <= maxWells) {
                    wells = Array.concat(wells, w);
                }
            }
        } else {
            // Single well number
            wellNum = parseInt(part);
            if (wellNum >= 1 && wellNum <= maxWells) {
                wells = Array.concat(wells, wellNum);
            }
        }
    }
    
    return wells;
}

// Create temporary directory in same location as first image
firstImageDir = File.getParent(imageFiles[0]);
tmpDir = firstImageDir + "/threshold_test_tmp/";
File.makeDirectory(tmpDir);
print("Working directory: " + tmpDir);

// Run in batch mode
setBatchMode(true);

// Process each image to create wells files
print("\n=== Step 1: Processing images ===");
wellsFiles = newArray(imageFiles.length);

for (i = 0; i < imageFiles.length; i++) {
    imagePath = imageFiles[i];
    imageName = File.getName(imagePath);
    print("Processing: " + imageName);
    
    // Open image
    open(imagePath);
    makeRectangle(rectX, rectY, rectWidth, rectHeight);
    
    // Exit batch mode temporarily
    setBatchMode(false);
    
    // Run Colony area plugin
    run("Colony area", "save=[" + tmpDir + "] plate=" + plateNum + " cols=" + plateCols + " rows=" + plateRows);
    
    // Re-enable batch mode
    setBatchMode(true);
    
    // Close any remaining images
    while (nImages > 0) {
        close();
    }
    
    // Store wells filename (plugin converts to .tif)
    wellsFiles[i] = "wells_" + replace(imageName, "\\.[^.]+$", ".tif");
    print("Created: " + wellsFiles[i]);
}

// Define threshold range
thresholds = newArray(41); // 50, 55, 60, ..., 250
for (i = 0; i < 41; i++) {
    thresholds[i] = 50 + (i * 5);
}

print("\n=== Step 2: Testing " + thresholds.length + " thresholds ===");

// Create results file
resultsPath = tmpDir + "threshold_test_results.csv";
resultsFile = File.open(resultsPath);
print(resultsFile, "Image,Well,Threshold,Area_Percent,Intensity_Percent");

// Process each wells file
for (fileIdx = 0; fileIdx < wellsFiles.length; fileIdx++) {
    wellsFilename = wellsFiles[fileIdx];
    
    // Extract original image name
    imageName = replace(wellsFilename, "wells_", "");
    imageName = replace(imageName, ".tif", "");
    
    print("\nAnalysing: " + imageName);
    
    // Test each threshold
    for (threshIdx = 0; threshIdx < thresholds.length; threshIdx++) {
        threshold = thresholds[threshIdx];
        
        // Open wells file
        open(tmpDir + wellsFilename);
        run("8-bit");
        
        // Get image properties
        height = getHeight();
        width = getWidth();
        numSlices = nSlices;
        
        // Calculate circular well correction ratio
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
        
        // Set measurements
        run("Set Measurements...", "area mean area_fraction redirect=None decimal=1");
        
        // Determine which wells to measure based on selection for this image
        wellsToMeasure = parseWellSelection(wellSelectionsPerImage[fileIdx], numSlices);
        
        // Measure each selected well
        for (wellIdx = 0; wellIdx < wellsToMeasure.length; wellIdx++) {
            wellNum = wellsToMeasure[wellIdx];
            
            // Select and duplicate this slice
            setSlice(wellNum);
            run("Duplicate...", "title=TempWell");
            
            // Apply threshold and create mask
            run("Duplicate...", "title=TempMask");
            selectWindow("TempMask");
            setThreshold(1, threshold);
            run("Convert to Mask");
            
            // Process intensity
            selectWindow("TempWell");
            run("Invert");
            imageCalculator("AND", "TempWell", "TempMask");
            
            // Measure
            selectWindow("TempWell");
            run("Measure");
            
            // Get results
            areafrac = getResult("%Area");
            area = getResult("Area");
            mean = getResult("Mean");
            
            // Apply corrections
            areafrac = areafrac / ratio;
            sumofi = area * mean;
            maxsumofi = area * 255 * ratio;
            intensityfrac = sumofi * 100 / maxsumofi;
            
            // Write to CSV
            print(resultsFile, imageName + "," + wellNum + "," + threshold + "," + 
                  d2s(areafrac, 2) + "," + d2s(intensityfrac, 2));
            
            // Clean up
            selectWindow("TempWell");
            close();
            selectWindow("TempMask");
            close();
            run("Clear Results");
        }
        
        // Close wells file
        selectWindow(wellsFilename);
        close();
        
        if (threshIdx % 10 == 0) {
            print("  Tested threshold " + threshold + "...");
        }
    }
}

// Close results file
File.close(resultsFile);

setBatchMode(false);

print("\n=== Step 3: Generating Plots ===");

// Read CSV data back
csvContent = File.openAsString(resultsPath);
lines = split(csvContent, "\n");

// Parse data (skip header)
imageWellLabels = newArray(0);
thresholdData = newArray(thresholds.length);
for (i = 0; i < thresholds.length; i++) {
    thresholdData[i] = thresholds[i];
}

// Build unique image-well combinations
for (i = 1; i < lines.length; i++) {
    if (lengthOf(lines[i]) > 0) {
        parts = split(lines[i], ",");
        label = parts[0] + "_Well" + parts[1];
        
        // Check if this label already exists
        found = false;
        for (j = 0; j < imageWellLabels.length; j++) {
            if (imageWellLabels[j] == label) {
                found = true;
                break;
            }
        }
        if (!found) {
            imageWellLabels = Array.concat(imageWellLabels, label);
        }
    }
}

print("Creating plots for " + imageWellLabels.length + " series...");

// Define colors for different series
colors = newArray("red", "blue", "green", "magenta", "orange", "cyan", "pink", "yellow");

// Build data arrays for all series
allAreaData = newArray(0);
allIntensityData = newArray(0);

// Process each image-well combination
for (labelIdx = 0; labelIdx < imageWellLabels.length; labelIdx++) {
    label = imageWellLabels[labelIdx];
    
    // Extract data for this label
    areaValues = newArray(thresholds.length);
    intensityValues = newArray(thresholds.length);
    dataIdx = 0;
    
    for (i = 1; i < lines.length; i++) {
        if (lengthOf(lines[i]) > 0) {
            parts = split(lines[i], ",");
            lineLabel = parts[0] + "_Well" + parts[1];
            
            if (lineLabel == label) {
                areaValues[dataIdx] = parseFloat(parts[3]);
                intensityValues[dataIdx] = parseFloat(parts[4]);
                dataIdx++;
            }
        }
    }
    
    // Store for plotting
    allAreaData = Array.concat(allAreaData, areaValues);
    allIntensityData = Array.concat(allIntensityData, intensityValues);
}

// Create and populate Area plot
Plot.create("Colony Area vs Threshold", "Threshold", "Area (%)");
Plot.setLimits(50, 250, 0, NaN);

for (labelIdx = 0; labelIdx < imageWellLabels.length; labelIdx++) {
    label = imageWellLabels[labelIdx];
    colorIdx = labelIdx % colors.length;
    
    // Extract this series' data
    startIdx = labelIdx * thresholds.length;
    endIdx = startIdx + thresholds.length;
    areaValues = Array.slice(allAreaData, startIdx, endIdx);
    
    Plot.setColor(colors[colorIdx]);
    Plot.add("line", thresholdData, areaValues);
}

// Add legend
legendText = "";
for (labelIdx = 0; labelIdx < imageWellLabels.length; labelIdx++) {
    legendText = legendText + imageWellLabels[labelIdx];
    if (labelIdx < imageWellLabels.length - 1) {
        legendText = legendText + "\n";
    }
}
Plot.setColor("black");
Plot.addLegend(legendText, "Auto");

Plot.show();

// Save area plot
saveAs("PNG", tmpDir + "area_vs_threshold.png");
print("Saved: " + tmpDir + "area_vs_threshold.png");

// Create and populate Intensity plot
Plot.create("Colony Intensity vs Threshold", "Threshold", "Intensity (%)");
Plot.setLimits(50, 250, 0, NaN);

for (labelIdx = 0; labelIdx < imageWellLabels.length; labelIdx++) {
    label = imageWellLabels[labelIdx];
    colorIdx = labelIdx % colors.length;
    
    // Extract this series' data
    startIdx = labelIdx * thresholds.length;
    endIdx = startIdx + thresholds.length;
    intensityValues = Array.slice(allIntensityData, startIdx, endIdx);
    
    Plot.setColor(colors[colorIdx]);
    Plot.add("line", thresholdData, intensityValues);
}

// Add legend
Plot.setColor("black");
Plot.addLegend(legendText, "Auto");

Plot.show();

// Save intensity plot
saveAs("PNG", tmpDir + "intensity_vs_threshold.png");
print("Saved: " + tmpDir + "intensity_vs_threshold.png");

print("\n=== Complete ===");
print("Results saved to: " + resultsPath);

// Show completion and open directory
showMessage("Test Complete!", "Threshold testing complete!\n\nResults saved to:\n" + resultsPath + "\n\nClick OK to open the directory.");

// Open tmp directory
osName = getInfo("os.name");
if (indexOf(osName, "Mac") >= 0) {
    exec("open", tmpDir);
} else if (indexOf(osName, "Windows") >= 0) {
    exec("explorer", tmpDir);
} else {
    exec("xdg-open", tmpDir);
}
