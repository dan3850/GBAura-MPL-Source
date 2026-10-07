# Source baseline

GBAura source baseline:
03d7a3f1f8fa577256fd6c5b1b1bb0536e732858

mGBA upstream:
https://github.com/mgba-emu/mgba

mGBA commit:
c3c8e5e813f245028de118a56734e1dc0f35ce2a

The git submodule at `upstream/mgba` is pinned to that exact commit.

The source-transforming module used by GBAura is:
`patches/mgba_mpl_modifications.cmake`

The additional MPL-covered GBAura file is:
`gbaura-mpl/SaveConverterUtil.java`
