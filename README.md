# papers-manager-bash

usage: 
```plo``` loads papers for last 15 minutes from Downloads
```plo -m 120``` loads papers for last 120 minutes from Downloads
```plo -f -a``` loads all and overwrites already processed papers from Downloads
```plo -t xxx -a``` loads all the papers from the xxx path

```pfi "hough"``` finds all the papers that contain keyword hough in any case, and then opens the chosen one using sioyek. Modify function f_pdf_open (don't remember exactly how it is called) if you want to use any other pdf editor.
```pfi dreamer -p``` search only papers (under 300kb text file)
```pfi dreamer -b``` search only books (300kb+ text files)
```pfi dreamer -w 2``` search only that were downloaded/opened for the last 2 weeks
