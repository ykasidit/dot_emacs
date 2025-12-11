My .emacs file
==============

My favorite flavor of vanilla emacs.

Usage
------

- backup your existing .emacs
  ```
  cd ~
  mv .emacs .emacs_backup
  ```
- clone this repo
  ```
  git clone git@github.com:ykasidit/dot_emacs.git
  ```
- make a link to this repo's .emacs in home
  ```
  ln -s dot_emacs/.emacs
- start emacs, install stuff that/if it complains missing (or remove/edit from .emacs as you prefer)

  (In my case I prefer to start from terminal as some LSP servers somehow have issues when start emacs from gui/menu)

  ```
  emacs
  ```
  
