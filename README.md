# Camera with image picker
## Whatsapp like UI 

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