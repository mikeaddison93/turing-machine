;;; turing-machine.el --- Single-tape Turing machine simulator -*- lexical-binding: t; -*-

;; Copyright (C) 2017 Diego A. Mundo
;; Author: Diego A. Mundo <diegoamundo@gmail.com>
;; URL: http://github.com/therockmandolinist/turing-machine
;; Git-Repository: git://github.com/therockmandolinist/turing-machine
;; Created: 2017-05-04
;; Version: 0.1.4
;; Keywords: turing machine simulation
;; Package-Requires: ((emacs "24.4") (cl-lib "0.6.1"))

;; This file is not part of GNU Emacs.

;; This program is free software: you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <http://www.gnu.org/licenses/>.


;;; Commentary:

;; This package provides an implementation of
;; http://morphett.info/turing/turing.html (a turing machine simulator) in
;; Emacs.


;;; Code:
(require 'cl-lib)

(defvar turing-machine-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "C-c C-c") #'turing-machine-execute)
    map))

(defvar turing-machine-highlights '((";.*" . font-lock-comment-face)
                                    ("^[^ ]+ [^ ]+" . font-lock-keyword-face)))

;;;###autoload
(define-derived-mode turing-machine-mode prog-mode "turing machine"
  "Major mode for editing turing machine code."
  (setq font-lock-defaults '(turing-machine-highlights))
  (setq comment-start ";")
  (when (featurep 'highlight-numbers)
    (highlight-numbers-mode -1)))

(setq turing-machine-mode-hook '(turing-machine--convenience))

(defun turing-machine--convenience ()
  "Turn off modes that interfere."
  (when (featurep 'highlight-numbers)
    (highlight-numbers-mode -1))
  (when (featurep 'rainbow-delimiters)
    (rainbow-delimiters-mode -1)))

;;; Define turing machine.
(defface turing-machine-current-face
  `((t (:foreground ,(face-attribute 'default :background) :background ,(face-attribute 'default :foreground) :height 200)))
  "Face of current place in turing machine tape."
  :group 'turing-machine)

(defface turing-machine-tape-face
  `((t (:height 200)))
  "Face of displayed tape."
  :group 'turing-machine)

(defcustom turing-machine-visual-spaces t
  "Whether to visualize spaces with an underscore"
  :group 'turing-machine
  :type 'boolean)

;; Set up an empty hash table of commands
(defvar turing-machine--commands (make-hash-table :test #'equal))

(defun turing-machine--buffer-to-hash ()
  "Parse the current buffer into a hash table of cammands."
  ;; Clear the table first.
  (clrhash turing-machine--commands)
  (let* ((file-string (buffer-substring-no-properties (point-min) (point-max)))
         (file-lines (cl-remove-if #'turing-machine--invalid-line
                                   (split-string file-string "\n")))
         (command-list (mapcar #'turing-machine--line-to-command file-lines)))
    (dolist (command command-list)
      (puthash (car command) (cadr command) turing-machine--commands))
    turing-machine--commands))

(defun turing-machine--invalid-line (line)
  "Check if LINE is empty or a comment."
  (or (string-empty-p line) (string-prefix-p ";" (string-trim line))))

(defun turing-machine--line-to-command (line)
  "Turn LINE into a grouped list like: `((a b) (c d e))'."
  (let ((elems (split-string (string-trim (car (split-string line ";"))) " ")))
    (list (reverse (nthcdr 3 (reverse elems))) (nthcdr 2 elems))))

(defun turing-machine--get-value (search)
  (string-trim
   (or (progn (search-forward-regexp search nil t)
              (match-string-no-properties 1))
       "0")))

;;;###autoload
(defun turing-machine-execute ()
  "Run the turing machine."
  (interactive)
  (save-excursion
    (goto-char (point-min))
    (let* ((commands (turing-machine--buffer-to-hash))
           (initial (replace-regexp-in-string
                     " "
                     "_"
                     (turing-machine--get-value "; INITIAL:\\(.*\\)")))
           (tape (cl-remove-if #'string-empty-p
                               (split-string (format "_%s_" initial) "")))
           (rate (string-to-number
                  (turing-machine--get-value "; RATE:\\(.*\\)")))
           (place 1)
           (state "0")
           (key (list "0" (cadr tape)))
           (wild-key (list state "*")))
      ;; If we still have a command associated with key
      (while (and (or (gethash key commands)
                      (gethash wild-key commands))
                  (not (string-prefix-p "halt" (car key))))
        ;; Update rate
        (redisplay t)
        (sleep-for rate)

        ;; Get things to do from hash table
        (cl-multiple-value-bind (new-char action new-state)
            (if (gethash key commands)
                (gethash key commands)
              (gethash wild-key commands))
          ;; Update the tape accordingly
          (when (not (string= new-char "*"))
            (setf (nth place tape) new-char))

          ;; Handle edges
          (cond ((string= action "l")
                 (cl-decf place)
                 (when (= place -1) ; Moving past beginning.
                   (push "_" tape)
                   (setq place 0)))
                ((string= action "r")
                 (cl-incf place)
                 (when (= place (length tape)) ; Moving past end.
                   (setq tape (append tape (list "_"))))))

          ;; Update the current state/key/wild
          (setq state new-state)
          (setq key (list state (nth place tape)))
          (setq wild-key (list state "*"))
          ;; Make visualization
          (let* ((tape-viz (copy-tree tape))
                 (tape-string
                  (concat (propertize
                           (string-join (cl-subseq tape-viz 0 place))
                           'face
                           'turing-machine-tape-face)
                          (propertize
                           (nth place tape-viz)
                           'face
                           'turing-machine-current-face)
                          (propertize
                           (string-join (cl-subseq tape-viz
                                                   (1+ place)
                                                   (length tape-viz)))
                           'face
                           'turing-machine-tape-face))))
            (with-current-buffer-window
             (get-buffer-create "*turing-machine*")
             nil
             nil
             (erase-buffer)
             (if turing-machine-visual-spaces
                 (insert tape-string)
               (insert (replace-regexp-in-string "_" " " tape-string)))))))
      (if (not (string-prefix-p "halt" (car key)))
          (message "No rule for state '%s' and char '%s'" state (nth place tape))
        (message "Done!")))))

(provide 'turing-machine)

;;; turing-machine.el ends here
