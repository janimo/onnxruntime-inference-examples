set ONNX_MODEL_URL="https://github.com/onnx/models/raw/main/vision/classification/mobilenet/model/mobilenetv2-12.onnx"
set ONNX_MODEL="mobilenetv2-12.onnx"
set KITTEN_IMAGE_URL="https://s3.amazonaws.com/model-server/inputs/kitten.jpg"
set KITTEN_IMAGE="images/kitten.jpg"
set LABEL_FILE_URL="https://s3.amazonaws.com/onnx-model-zoo/synset.txt"
set LABEL_FILE="synset.txt"

IF [%1] == [] GOTO Help

SET ORT_ROOT=%1
SET ORT_BIN=%2
SET WORKSPACE=%~dp0

IF NOT EXIST %ORT_ROOT%\include\onnxruntime\core\session\onnxruntime_cxx_api.h (
    ECHO %ORT_ROOT%\include\onnxruntime\core\session\onnxruntime_cxx_api.h not found
    GOTO Help
)

IF NOT EXIST %ORT_BIN%\onnxruntime.dll (
    ECHO %ORT_BIN%\onnxruntime.dll not found
    GOTO Help
)

pushd %WORKSPACE%

REM Download mobilenetv2-12 onnx model file
IF NOT EXIST %ONNX_MODEL% (
    powershell -Command "Invoke-WebRequest %ONNX_MODEL_URL% -Outfile %ONNX_MODEL%" )
REM Download kitten.jpg
IF NOT EXIST %KITTEN_IMAGE% (
    mkdir images
    powershell -Command "Invoke-WebRequest %KITTEN_IMAGE_URL% -Outfile %KITTEN_IMAGE%" )
REM Download label file
IF NOT EXIST %LABEL_FILE% (
    powershell -Command "Invoke-WebRequest %LABEL_FILE_URL% -Outfile %LABEL_FILE%" )

REM Generate QDQ model, fixed shape float32 model, fixed shape QDQ model, kitten_input.raw
python mobilenetv2_helper.py

where /q cmake.exe
IF ERRORLEVEL 1 (
    ECHO Ensure Visual Studio 17 2022 is installed and open a VS Dev Cmd Prompt
    GOTO EXIT
)

REM build with Visual Studios 2022 ARM 64-bit Native
cmake.exe -S . -B build\ -G "Visual Studio 17 2022" -DONNXRUNTIME_ROOTDIR=%ORT_ROOT% -DCMAKE_BUILD_TYPE=Release

REM Copy ORT libraries for linker to build.
cd build
MSBuild.exe .\qnn_ep_sample.sln /property:Configuration=Release /p:Platform="ARM64"

REM Copy ORT libraries for executable to run.
cd Release
copy /y %ORT_BIN%\onnxruntime.dll .
copy /y %ORT_BIN%\qnncpu.dll .
copy /y %ORT_BIN%\QnnHtp.dll .
copy /y %ORT_BIN%\QnnHtpPrepare.dll .
copy /y %ORT_BIN%\QnnHtpV68Stub.dll .
copy /y %ORT_BIN%\QnnSystem.dll .
copy /y %ORT_BIN%\libQnnHtpV68Skel.so .
copy /y ..\..\mobilenetv2-12_shape.onnx .
copy /y ..\..\mobilenetv2-12_quant_shape.onnx .
copy /y ..\..\kitten_input.raw .
copy /y ..\..\synset.txt .

REM run with QNN CPU backend
qnn_ep_sample.exe --cpu kitten_input.raw

REM run with QNN HTP backend
qnn_ep_sample.exe --htp kitten_input.raw

:EXIT
popd
exit /b

:HELP
ECHO HELP:    run_qnn_ep_sample.bat PATH_TO_ORT_ROOT_WITH_INCLUDE_FOLDER PATH_TO_ORT_BINARIES
ECHO Example: run_qnn_ep_sample.bat C:\src\onnxruntime C:\src\onnxruntime\build\Windows\Release\Release