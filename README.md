# texparser

Goal of this project is to provide tool that can parse LaTeX source files and
convert them to format suitable for tasks such as: 

- grammar checking 
- prose linting 
- syntax linting 
- word counting 
- etc.

It should be possible to use the output of these actions and:

- display place from the original TeX file that is reported by linters
- compare text updated by external tool (for example Grammarly) to the original
  LaTeX source and create a patch file that can be used to insert changes to
  the original document.

## Not goals

- convert LaTeX to HTML -- there are too many of such tools, no need for
  another one. I am developer of [TeX4ht](https://tug.org/tex4ht/), so I can
  recommend this one. If you have any questions regarding LaTeX to HTML, feel
  free to ask me.
- support for other encodings than UTF8 -- it is used by LaTeX by default today
  anyway.


