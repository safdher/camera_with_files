# Camera with image picker
## Whatsapp like UI 

A fork from the [CameraWithFiles](https://github.com/safdher/camera_with_files) project created by _safdher_.

_As the original project is apparently not currently being maintained, I decided to keep this alternate version of the project._

[![N|Solid](https://drive.google.com/uc?export=download&id=1DsQ47pXQfhFhFnHA_xycXySI2_wW669F)]()

Camera with image picker works on android, ios and Web.
- Multiple image selection.
- optional single image selection.
- camera switching
- flash light



## Usage

Navigate to the camerApp page and after selecting image or taking photo from camera will return the selected list of files
## For Multiple image selection
```sh
List<File> data = await Navigator.of(context).push(MaterialPageRoute<List<File>>(
builder:(BuildContext context)=> const CameraApp(
//multiple image selection flag
isMultiple :true
),),);
```
## For Single image selection
data[0] will contain the file.
```sh
List<File> data = await Navigator.of(context).push(MaterialPageRoute<List<File>>(
builder:(BuildContext context)=> const CameraApp(
//multiple image selection flag
isMultiple :false
),),);
```

# Album related
## For storing IOs files in the documents folder

Add this to your info.plist:
<key>LSSupportsOpeningDocumentsInPlace</key>
<true/>
<key>UIFileSharingEnabled</key>
<true/>

Minumum platform versions: Android 16, iOS 9.0, macOS 10.15.

Android: Android config preparation.
iOS: iOS config preparation.
macOS: Pretty much the same with iOS.