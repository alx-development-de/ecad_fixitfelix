@echo off

pp -o .\dist\FixItFelix.exe -I lib -l .\lib\LibXML.xs.dll -l .\lib\LibXSLT.xs.xs.dll -l .\lib\Expat.xs.dll -l .\lib\Encode.xs.dll -l .\lib\encoding.xs.dll -l .\lib\Parser.xs.dll -l .\lib\libexpat-1__.dll .\script\FixItFelix.pl

pause
