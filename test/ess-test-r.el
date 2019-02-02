;;; ess-test-r.el --- ESS tests for R  -*- lexical-binding: t; -*-
;;
;; This file is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation; either version 2, or (at your option)
;; any later version.
;;
;; This file is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.
;;
;; A copy of the GNU General Public License is available at
;; https://www.r-project.org/Licenses/
;;
;;; Commentary:
;;

(require 'ert)
(require 'ess-r-mode)
(require 'ess-test-r-utils)
(require 'cc-mode)
(require 'imenu)

;;; R

;;; Code:

(ert-deftest ess-r-inherits-prog-mode-test ()
  (let ((prog-mode-hook (lambda () (setq ess-test-prog-hook t))))
    (with-r-file nil
      (should (derived-mode-p 'prog-mode))
      (should ess-test-prog-hook)
      (should
       ;; Test that prog-mode-map is a keymap-parent
       (let ((map (current-local-map))
             found)
         (while (and map (not found))
           (if (eq (keymap-parent map) prog-mode-map)
               (setq found t)
             (setq map (keymap-parent map))))
         found)))))

(ert-deftest ess-build-eval-command-R-test ()
  (let ((command "command(\"string\")")
        (ess-dialect "R"))
    (should (string= (ess-build-eval-command command)
                     ".ess.eval(\"command(\\\"string\\\")\", visibly = FALSE, output = FALSE)\n"))
    (should (string= (ess-build-eval-command command nil t)
                     ".ess.eval(\"command(\\\"string\\\")\", visibly = FALSE, output = TRUE)\n"))
    (should (string= (ess-build-eval-command command t t "file.ext" "foo")
                     ".ess.ns_eval(\"command(\\\"string\\\")\", visibly = TRUE, output = TRUE, package = 'foo', verbose = TRUE, file = 'file.ext')\n"))))

(ert-deftest ess-build-load-command-R-test ()
  (let ((ess-dialect "R"))
    (should (string= (ess-build-load-command "file.ext")
                     ".ess.source('file.ext', visibly = FALSE, output = FALSE)\n"))
    (should (string= (ess-build-load-command "file.ext" t t)
                     ".ess.source('file.ext', visibly = TRUE, output = TRUE)\n"))
    (should (string= (ess-build-load-command "file.ext" nil t "foo")
                     ".ess.ns_source('file.ext', visibly = FALSE, output = TRUE, package = 'foo', verbose = TRUE)\n"))))

(ert-deftest inferior-ess-inherits-from-comint-test ()
  (let ((inhibit-message ess-inhibit-message-in-tests))
    (with-temp-buffer
      (inferior-ess-r-mode)
      ;; Derive from comint
      (should (derived-mode-p 'comint-mode))
      (should
       ;; Test that comint-mode-map is a keymap-parent
       (let ((map (current-local-map))
             found)
         (while (and map (not found))
           (if (eq (keymap-parent map) comint-mode-map)
               (setq found t)
             (setq map (keymap-parent map))))
         found)))))

(ert-deftest ess-r-send-single-quoted-strings-test ()
  (with-r-running nil
    (insert "'hop'\n")
    (let (ess-eval-visibly)
      (should (output= (ess-eval-buffer nil)
                       "[1] \"hop\"")))))

(ert-deftest ess-r-send-double-quoted-strings-test ()
  (with-r-running nil
    (insert "\"hop\"\n")
    (let (ess-eval-visibly)
      (should (output= (ess-eval-buffer nil)
                       "[1] \"hop\"")))))

(ert-deftest ess-eval-line-test ()
  (with-r-running nil
    (insert "1 + 1")
    (let (ess-eval-visibly)
      (should (output= (ess-eval-line)
                       "[1] 2")))
    (let ((ess-eval-visibly t))
      (should (output= (ess-eval-line)
                       "1 + 1\n[1] 2")))))

(ert-deftest ess-eval-region-test ()
  (with-r-running nil
    (insert "1 + \n1")
    (let (ess-eval-visibly)
      (should (output= (ess-eval-region (point-min) (point-max) nil)
                       ;; We seem to be emitting an extra + here:
                       "+ [1] 2")))
    (let ((ess-eval-visibly t))
      (should (output= (ess-eval-region (point-min) (point-max) nil)
                       "1 + \n1\n[1] 2")))))

(ert-deftest ess-eval-function ()
  (with-r-running nil
    (let (ess-eval-visibly)
      (insert "x <- function(a){\n a + 1\n}")
      (forward-line -1)
      (ess-eval-function)
      (delete-region (progn (beginning-of-defun) (point))
                     (progn (end-of-defun) (point)))
      (insert "x(1)")
      (should (output= (ess-eval-region (point-min) (point-max) nil)
                       "+ + > [1] 2")))))

(ert-deftest ess-r-eval-rectangle-mark-mode-test ()
  (with-r-running nil
    (insert "x <- 1\nx\nx + 1\nx  +  2\n")
    (let (ess-eval-visibly)
      (should (output= (progn
                         (goto-char (point-min))
                         (transient-mark-mode)
                         (rectangle-mark-mode)
                         (forward-line 3)
                         (end-of-line)
                         (ess-eval-region-or-line-and-step))
                       "> [1] 1\n> [1] 2\n> [1] 3")))))

(ert-deftest ess-set-working-directory-test ()
  (with-r-running nil
    (ess-set-working-directory "/")
    (ess-eval-linewise "getwd()" 'invisible)
    (should (output= (ess-eval-buffer nil)
                     "setwd('/')\n> [1] \"/\""))
    (should (string= default-directory "/"))))

(ert-deftest ess-inferior-force-test ()
  (with-r-running nil
    (should (equal (ess-get-words-from-vector "letters[1:2]\n")
                   (list "a" "b")))))

;;; Namespaced evaluation

(ert-deftest ess-r-run-presend-hooks-test ()
  (with-r-running nil
    (let ((ess-presend-filter-functions (list (lambda (string) "\"bar\"")))
          (ess-r-evaluation-env "base")
          ess-eval-visibly)
      (insert "\"foo\"\n")
      (should (output= (ess-eval-region (point-min) (point-max) nil)
                       "[1] \"bar\"")))))

(ert-deftest ess-r-namespaced-eval-no-sourced-message-test ()
  (with-r-running nil
    (let ((ess-r-evaluation-env "base")
          ess-eval-visibly)
      (insert "\"foo\"\n")
      (should (output= (ess-eval-region (point-min) (point-max) nil)
                       "[1] \"foo\"")))))

(ert-deftest ess-r-namespaced-eval-no-srcref-in-errors-test ()
  ;; Fails since https://github.com/emacs-ess/ESS/commit/3a7d913
  (when nil
    (with-r-running nil
      (let ((ess-r-evaluation-env "base")
            (error-msg "Error: unexpected symbol")
            ess-eval-visibly)
        (insert "(foo bar)\n")
        (let ((output (output (ess-eval-region (point-min) (point-max) nil))))
          (should (string= (substring output 0 (length error-msg))
                           error-msg)))))))


;;; Misc

(ert-deftest ess-r-makevars-mode-test ()
  (save-window-excursion
    (mapc (lambda (file)
            (switch-to-buffer (find-file-noselect file))
            (should (eq major-mode 'makefile-mode)))
          `(,(expand-file-name "Makevars" ess-test-fixtures-directory)
            ,(expand-file-name "Makevars.win" ess-test-fixtures-directory)))))

(ert-deftest ess-find-newest-date-test ()
  (should (equal (ess-find-newest-date '(("2003-10-04" . "R-1.7")
                                         ("2006-11-19" . "R-2.2")
                                         ("2007-07-01" . "R-dev")
                                         ("-1"         . "R-broken")
                                         ("2005-12-30" . "R-2.0")))
                 "R-dev")))

(ert-deftest ess-insert-S-assign-test ()
  ;; one call should insert assignment:
  (should
   (string= " <- "
            (ess-r-test-with-temp-text ""
              (setq last-input-event ?_)
              (call-interactively 'ess-insert-S-assign)
              (buffer-substring (point-min) (point-max))))))

(ert-deftest ess-skip-thing-test ()
  (should (eql 18
               (ess-r-test-with-temp-text "x <- function(x){\n mean(x)\n }\n \n \n x(3)\n "
                 (goto-char (point-min))
                 (ess-skip-thing 'line)
                 (point))))
  (should (eql 30
               (ess-r-test-with-temp-text "x <- function(x){\n mean(x)\n }\n \n \n x(3)\n "
                 (goto-char (point-min))
                 (ess-skip-thing 'function)
                 (point))))
  (should (eql 31
               (ess-r-test-with-temp-text "x <- function(x){\n mean(x)\n }\n \n \n x(3)\n "
                 (goto-char (point-min))
                 (ess-skip-thing 'paragraph)
                 (point))))

  ;; The following fails because end-of-defun assume that beggining-of-defun
  ;; always moves the pointer. We currently don't in ess-r-beginning-of-function
  ;; when there is no function. This might change when we have aproper
  ;; ess-r-beggining-of-defun.
  ;; (should (eql 1 (ess-r-test-with-temp-text "mean(1:10)"
  ;;                  (goto-char (point-min))
  ;;                  (ess-skip-thing 'function)
  ;;                  (point))))
  )

(ert-deftest ess-next-code-line-test ()
  (should (eql 5
               (ess-r-test-with-temp-text "1+1\n#2+2\n#3+3\n4+4"
                 (let ((ess-eval-empty t))
                   (goto-char (point-min))
                   (ess-next-code-line)
                   (point)))))
  (should (eql 15
               (ess-r-test-with-temp-text "1+1\n#2+2\n#3+3\n4+4"
                 (let (ess-eval-empty)
                   (goto-char (point-min))
                   (ess-next-code-line)
                   (point))))))

(ert-deftest ess-Rout-file-test ()
  (let* ((file (expand-file-name "file.Rout" ess-test-fixtures-directory))
         (buf (or (find-buffer-visiting file)
                  (find-file-noselect file))))
    (with-current-buffer buf
      (should (eq major-mode 'ess-r-transcript-mode))
      (goto-char (point-min))
      (font-lock-default-fontify-buffer)
      (should (eq (face-at-point) 'font-lock-function-name-face)))))

(ert-deftest inferior-ess-r-fontification-test ()
  (with-r-running nil
    (with-ess-process-buffer nil
      ;; Function-like keywords
      (should (eq major-mode 'inferior-ess-r-mode))
      (insert-fontified "for")
      (should (not (face-at -1)))
      (insert-fontified "(")
      (should (eq (face-at -2) 'ess-keyword-face))
      ;; `in` keyword
      (insert-fontified "foo in bar)")
      (search-backward "in")
      (should (eq (face-at-point) 'ess-keyword-face))
      (erase-buffer)
      (insert-fontified "for foo in bar")
      (search-backward "in")
      (should (not (face-at-point))))))

;; roxy
(ert-deftest ess-roxy-preview-Rd-test ()
  (with-r-running nil
    (when (member "roxygen2" (ess-installed-packages))
      (should
       (string= "% Generated by roxygen2: do not edit by hand
\\name{add}
\\alias{add}
\\title{Add together two numbers.
add(10, 1)}
\\usage{
add(x, y)
}
\\description{
Add together two numbers. add(10, 1)
} 
"
                (with-temp-buffer
                  (R-mode)
                  (ess-roxy-mode)
                  (insert
                   "##' Add together two numbers.
##' add(10, 1)
add <- function(x, y) {
  x + y
}")
                  (goto-char (point-min))
                  (ess-roxy-preview-Rd)
                  ;; Delete the reference to the file which isn't
                  ;; reproducible across different test environments
                  (goto-char (point-min))
                  (forward-line 1)
                  (kill-whole-line)
                  (buffer-substring-no-properties (point-min) (point-max))))))))

(ert-deftest ess-roxy-cpp-test ()
  ;; Test M-q
  (should (string=
           "//' Title
//'
//' @param Lorem ipsum dolor sit amet, consectetur adipiscing elit,
//'   sed do eiusmod.
//' @param Lorem ipsum dolor sit amet, consectetur adipiscing elit,
//'   sed do eiusmod.
//' @examples
//' mean()
"
           (ess-cpp-test-with-temp-text
               "//' Title
//'
//' @param Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod.
//' @param ¶Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod.
//' @examples
//' mean()
"
             (c-fill-paragraph)
             (buffer-substring-no-properties (point-min) (point-max)))))
  ;; Test newline
  (should (string=
           "//'\n//' "
           (ess-cpp-test-with-temp-text "//' ¶"
             (ess-roxy-newline-and-indent)
             (buffer-substring-no-properties (point-min) (point-max)))))
  (should (string=
           "//\n"
           (ess-cpp-test-with-temp-text "//¶"
             (ess-roxy-newline-and-indent)
             (buffer-substring-no-properties (point-min) (point-max))))))

;; Navigation
(ert-deftest ess-r-function-beg-end-test ()
  (ess-r-test-with-temp-text
      "x <- function(a){\n  a + 1\n}"
    (search-forward "(a)")
    (beginning-of-defun)
    (should (eql (point) 1))
    (search-forward "(a)")
    (end-of-defun)
    (should (eql (point) 28))))

(ert-deftest ess-r-beginning/end-of-defun-test ()
  (with-r-file (expand-file-name "navigation.R" ess-test-fixtures-directory)
    (goto-char (point-min))
    (end-of-defun 1)
    (should (looking-back "fn1\n"))
    (beginning-of-defun 1)
    (should (looking-at "fn1 <-"))
    (beginning-of-defun -1)
    (should (looking-at "fn2 <-"))
    (end-of-defun 2)
    (should (looking-back "fn3\n"))
    (beginning-of-defun)
    (should (looking-at "fn3 <-"))
    (end-of-defun 2)
    (should (looking-back "setMethod\n"))
    (end-of-defun 1)
    (should (looking-back "fn4\n"))
    (beginning-of-defun 1)
    (should (looking-at "fn4 <-"))
    (beginning-of-defun 1)
    (should (looking-at "setMethod("))
    (end-of-defun -1)
    (should (looking-back "fn3\n"))))

(ert-deftest ess-r-beginning/end-of-function-test ()
  (with-r-file (expand-file-name "navigation.R" ess-test-fixtures-directory)
    (goto-char (point-min))
    (ess-r-end-of-function 1)
    (should (looking-at " ## end of fn1"))
    (ess-r-beginning-of-function 1)
    (should (looking-at "fn1 <-"))
    (ess-r-beginning-of-function -1)
    (should (looking-at "fn2 <-"))
    (ess-r-end-of-function)
    (ess-r-end-of-function)
    (should (looking-at " ## end of fn3\n"))
    (ess-r-beginning-of-function)
    (should (looking-at "fn3 <-"))
    (ess-r-end-of-function)
    (ess-r-end-of-function)
    (should (looking-at " ## end of setMethod"))
    (ess-r-end-of-function 1)
    (should (looking-at " ## end of fn4"))
    (ess-r-beginning-of-function 1)
    (should (looking-at "fn4 <-"))
    (ess-r-beginning-of-function 1)
    (should (looking-at "setMethod("))
    (ess-r-end-of-function -1)
    (should (looking-at " ## end of fn3"))))

(ert-deftest ess-r-goto-beginning/end-of-function-or-para-test ()
  (with-r-file (expand-file-name "navigation.R" ess-test-fixtures-directory)
    (goto-char (point-min))
    (ess-goto-end-of-function-or-para)
    (should (looking-back "fn1\n"))
    (ess-goto-beginning-of-function-or-para)
    (should (looking-at "fn1 <-"))
    (ess-goto-end-of-function-or-para)
    (ess-goto-end-of-function-or-para)
    (should (looking-back "fn2\n"))
    (ess-goto-end-of-function-or-para)
    (should (looking-back "fn3\n"))
    (ess-goto-end-of-function-or-para)
    (should (looking-back "par1\n"))
    (ess-goto-end-of-function-or-para)
    (should (looking-back "setMethod\n"))
    (ess-goto-beginning-of-function-or-para)
    (should (looking-at "setMethod"))
    (ess-goto-beginning-of-function-or-para)
    (should (looking-at "par1 <-"))
    (ess-goto-beginning-of-function-or-para)
    (should (looking-at "fn3 <-"))))

(ert-deftest ess-r-beggining/end-of-defun-ignore-inner-fn-test ()
  (with-r-file (expand-file-name "navigation.R" ess-test-fixtures-directory)
    (re-search-forward "fn5_body")
    (beginning-of-defun)
    (should (looking-at "fn4 <- "))
    (re-search-forward "fn5_body")
    (end-of-defun)
    (should (looking-back "fn4\n"))))

(ert-deftest ess-r-comment-dwim-test ()
  "Test `comment-dwim' and Bug #434."
  (let ((ess-default-style 'RRR))
    (ess-r-test-with-temp-text "#¶ "
      (let ((ess-indent-with-fancy-comments t))
        (comment-dwim nil)
        (should (eql 42 (current-column)))
        (ess-indent-or-complete)
        (should (eql 42 (current-column)))))
    (ess-r-test-with-temp-text "#¶ "
      (let ((ess-indent-with-fancy-comments nil))
        (comment-dwim nil)
        (should (eql 2 (current-column)))
        (ess-indent-or-complete)
        (should (eql 2 (current-column)))))))

;; imenu
(ert-deftest ess-imenu-test ()
  (ess-r-test-with-temp-text
      "
library(knitr)
x <- function(a) mean(a)

y <- function(c){
  sum(c)
}

the_dat <- read.csv(\"foo.csv\")"
    (let ((result (funcall imenu-create-index-function)))
      (should (equal (car (nth 0 result)) "Data"))
      (should (equal (caadr (nth 0 result)) "the_dat"))
      (should (equal (car (nth 1 result)) "Package"))
      (should (equal (caadr (nth 1 result)) "knitr"))
      (should (equal (car (nth 2 result)) "Functions"))
      (should (equal (caadr (nth 2 result)) "x"))
      (should (equal (caaddr (nth 2 result)) "y")))))

(provide 'ess-test-r)

;;; ess-test-r.el ends here