# toshiba
## Usage
```
toshiba_remap.exe -in bank1.img -in bank2.img -out output.img -bmsize (number)
```
- `-bmsize (number)`: The output file size in 16K blocks.
- `-w54t`: If the image is coming from W54T.
  - W54T has somewhat different FTL structures (if you can call them "structures", it's literally a bunch of 3-byte records in OOB area) and if you don't pass it, you'll end up with an empty output.
