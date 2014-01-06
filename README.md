# font-coverage

This script is for scanning font files and listing their unicode coverage by unicode blocks. Currently truetype fonts (TTF), opentype fonts (OTF) and truetype collections (TTC) are supported.

It is inspired from the versatile [FontForge](http://fontforge.org/) suite (actual Unicode characters covered by font is listed under `Element` &rarr; `Font Info`), as well as [ttfcoverage](http://everythingfonts.com/ttfcoverage) website.

### Requirement

* [Font::TTF](http://search.cpan.org/~mhosken/Font-TTF-1.03/) Perl module
* [Text::CSV](http://search.cpan.org/~makamaka/Text-CSV-1.32/) (optional, to produce CSV output)

Note that due to certain bug in Font::TTF this script may not be able to read all fonts embedded inside TTCs.

### Usage

    font-coverage.pl [option...] FONT_FILE...

Invoking `font-coverage.pl -h` produces a list of options.

Usage example:

    # font-coverage.pl a.ttf dir/b.otf moredir/c.ttc
    # font-coverage.pl -i -s -z -u 5.2.0 a.ttf

Running the script on [Musica](http://users.teilar.gr/~g1951d/) truetype font produces output like:

```
......
Geometric Shapes (U+25A0-U+25FF) => 96 / 1 / 0
Miscellaneous Symbols (U+2600-U+26FF) => 256 / 7 / 0
Byzantine Musical Symbols (U+1D000-U+1D0FF) => 246 / 246 / 0
Musical Symbols (U+1D100-U+1D1FF) => 220 / 220 / 11
Ancient Greek Musical Notation (U+1D200-U+1D24F) => 70 / 70 / 0
Supplementary Private Use Area-A (U+F0000-U+FFFFF) => 0 / 0 / 58
```

Numbers appearing in output represents, in order:

1. Total number of code points assigned for specific Unicode range
1. Number of glyphs **assigned** in unicode standard for that range
1. Number of glyphs **not assigned** in unicode standard for that range

So the output snippet above means all Music symbol related unicode ranges are 100% covered (though not for other ranges), and there are 11 extra glyphs in Musical Symbols not used by current version of Unicode.

**Note**: all code points in Control Chars, Surrogates and Private Use Areas are treated as unassigned.


### Support for other Unicode versions

The `-u` option allows one to compare the font against alternative versions of Unicode (by default current version 6.3.0 is used). Include files for latest update of all major Unicode versions (2.1 onwards) have been pre-generated, but if one somehow wants to compare against other versions, it is possible to invoke `gen-include-file.pl` to generate the ones you need. Please refer to the script itself for detail.

### Todo

* user options to show/hide PUA
* combined count of all fonts
* points in No_block & non-unicode glyphs not handled
* well defined codepoint ignore list
* cross platform support
* scan *all* fonts used by system to get an idea about the system&rsquo;s unicode coverage in general

