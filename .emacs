;; --- Environment overrides ---
(setenv "LSP_USE_PLISTS" "true")
(setenv "BUILDKIT_PROGRESS" "plain")
;; vterm children (claude's Ctrl+O v, git, etc.) open files in this Emacs
(setenv "EDITOR" "emacsclient")
(setenv "VISUAL" "emacsclient")
(require (quote server))
(unless (server-running-p) (server-start))
;; GUI Emacs doesn't source the shell profile, so nvm's node bin is invisible
;; (breaks agent-shell's claude-agent-acp lookup). Put it on PATH/exec-path.
;; ponytail: picks last dir lexicographically; fine with one node version
(let ((node-bin (car (last (file-expand-wildcards "~/.nvm/versions/node/*/bin")))))
  (when node-bin
    (setenv "PATH" (concat node-bin ":" (getenv "PATH")))
    (add-to-list 'exec-path node-bin)))

;; Keep vterm TUIs (e.g. claude) from recentering-jumping on rapid redraws
(add-hook 'vterm-mode-hook
          (lambda ()
            (setq-local scroll-conservatively 101)
            (setq-local scroll-margin 0)
            (setq-local scroll-step 1)
            ;; stop sub-line vertical "bounce" while the TUI repaints
            (setq-local auto-window-vscroll nil)
            (setq-local fast-but-imprecise-scrolling t)
            ;; THE main bounce fix: when the cursor lands on the last,
            ;; partially-clipped screen line (where claude's spinner/status
            ;; block sits), Emacs scrolls up to fully reveal it, the TUI
            ;; repaints, and it scrolls back — that oscillation is the bounce.
            ;; Letting the bottom line stay partially visible kills it.
            (setq-local make-cursor-line-fully-visible nil)
            ;; pin scrolling to the minimum, never recenter/aggressive-scroll
            (setq-local scroll-up-aggressively 0.0)
            (setq-local scroll-down-aggressively 0.0)
            ;; if a status line ever wraps at the window edge the buffer
            ;; height oscillates by a line -> bounce; truncate instead
            (setq-local truncate-lines t)))

;; vterm output cadence: batch burst redraws so the full-screen TUI doesn't
;; flicker. Default 0.1 is fine; a touch higher coalesces more without
;; noticeable lag. (Do NOT set nil/lower — that worsens flicker.)
(setq vterm-timer-delay 0.15)

;; keep enough scrollback to browse old claude output (default is 1000 lines)
(setq vterm-max-scrollback 100000)

;; -*- lexical-binding: t; -*-
(require 'package)

(setq package-archives
      '(("melpa" . "https://melpa.org/packages/")
        ("melpa-stable" . "https://stable.melpa.org/packages/")
        ("gnu" . "https://elpa.gnu.org/packages/")))

(setq flycheck-navigation-minimum-level 'error)

(package-initialize)
(unless package-archive-contents
  (package-refresh-contents))

(require 'lsp-mode)
(use-package lsp-jedi
  :ensure t)
(add-hook 'python-mode-hook #'lsp)
(add-hook 'c-mode-hook #'lsp)
(add-hook 'go-mode-hook #'lsp)
(add-to-list 'lsp-disabled-clients 'pylsp)


(defun lsp-booster--advice-json-parse (old-fn &rest args)
  "Try to parse bytecode instead of json."
  (or
   (when (equal (following-char) ?#)
     (let ((bytecode (read (current-buffer))))
       (when (byte-code-function-p bytecode)
         (funcall bytecode))))
   (apply old-fn args)))
(advice-add (if (progn (require 'json)
                       (fboundp 'json-parse-buffer))
                'json-parse-buffer
              'json-read)
            :around
            #'lsp-booster--advice-json-parse)

(defun lsp-booster--advice-final-command (old-fn cmd &optional test?)
  "Prepend emacs-lsp-booster command to lsp CMD."
  (let ((orig-result (funcall old-fn cmd test?)))
    (if (and (not test?)                             ;; for check lsp-server-present?
             (not (file-remote-p default-directory)) ;; see lsp-resolve-final-command, it would add extra shell wrapper
             lsp-use-plists
             (not (functionp 'json-rpc-connection))  ;; native json-rpc
             (executable-find "emacs-lsp-booster"))
        (progn
          (when-let ((command-from-exec-path (executable-find (car orig-result))))  ;; resolve command from exec-path (in case not found in $PATH)
            (setcar orig-result command-from-exec-path))
          (message "Using emacs-lsp-booster for %s!" orig-result)
          (cons "emacs-lsp-booster" orig-result))
      orig-result)))
(advice-add 'lsp-resolve-final-command :around #'lsp-booster--advice-final-command)

(setq inhibit-startup-message t) ; Disable startup message
(delete-selection-mode 1)
(tool-bar-mode 0)
(menu-bar-mode 0)
(add-to-list 'custom-theme-load-path "~/.emacs.d/themes/") 

(global-set-key (kbd "S-C-<left>") 'shrink-window-horizontally)
(global-set-key (kbd "S-C-<right>") 'enlarge-window-horizontally)
(global-set-key (kbd "S-C-<down>") 'shrink-window)
(global-set-key (kbd "S-C-<up>") 'enlarge-window)

(global-set-key [M-left] 'windmove-left)          ; move to left windnow
(global-set-key [M-right] 'windmove-right)        ; move to right window
(global-set-key [M-up] 'windmove-up)              ; move to upper window
(global-set-key [M-down] 'windmove-down)          ; move to downer window

;; backup in one place. flat, no tree structure
(setq backup-directory-alist '(("" . "~/.emacs.d/emacs-backup")))

(setq compile-command "make")
(setq gc-cons-threshold 3500000)

(defun c-lineup-arglist-tabs-only (ignored)
  "Line up argument lists by tabs, not spaces"
  (let* ((anchor (c-langelem-pos c-syntactic-element))
	 (column (c-langelem-2nd-pos c-syntactic-element))
	 (offset (- (1+ column) anchor))
	 (steps (floor offset c-basic-offset)))
    (* (max steps 1)
       c-basic-offset)))

(add-hook 'c-mode-common-hook
          (lambda ()
            ;; Add kernel style
            (c-add-style
             "linux-tabs-only"
             '("linux" (c-offsets-alist
                        (arglist-cont-nonempty
                         c-lineup-gcc-asm-reg
                         c-lineup-arglist-tabs-only))))))

(add-hook 'c-mode-hook
          (lambda ()
            (let ((filename (buffer-file-name)))
              ;; Enable kernel mode for the appropriate files
              (when (and filename
                         (string-match (expand-file-name "/")
                                       filename))
                (setq indent-tabs-mode t)
                (c-set-style "linux-tabs-only")))))
(setq lsp-clients-clangd-executable "/usr/bin/clangd")
(setq-default search-invisible t)
(setq compilation-skip-threshold 2)
(setq lsp-inlay-hint-enable t)
(lsp-inlay-hints-mode 1)


(setq counsel-rg-base-command "rg --no-heading --line-number --color never --no-messages %s || true")
(define-key global-map (kbd "C-S-f") 'counsel-rg)
(custom-set-variables
 ;; custom-set-variables was added by Custom.
 ;; If you edit it by hand, you could mess it up, so be careful.
 ;; Your init file should contain only one such instance.
 ;; If there is more than one, they won't work right.
 '(custom-enabled-themes '(shaman))
 '(custom-safe-themes
   '("41100b6e7f88e41cc81940dc54607636525bbf74f8e580ee7ab99486e186d921"
     default))
 '(package-selected-packages nil)
 '(package-vc-selected-packages
   '((claude-code :url "https://github.com/stevemolitor/claude-code.el"))))


(custom-set-faces
 ;; custom-set-faces was added by Custom.
 ;; If you edit it by hand, you could mess it up, so be careful.
 ;; Your init file should contain only one such instance.
 ;; If there is more than one, they won't work right.
 )

(use-package claude-code
  :ensure t
  :vc (:url "https://github.com/stevemolitor/claude-code.el" :rev :newest)
  :config
  (claude-code-mode)
  :bind-keymap ("C-c c" . claude-code-command-map))
