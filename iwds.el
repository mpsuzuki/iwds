;;; iwds.el --- IWDS XML data processing  -*- lexical-binding: t -*-

;; Copyright (C) 2014 Kawabata Taichi

;; Filename: iwds.el
;; Package-Requires: ((emacs "24.3") (dash "1.0.0"))
;; Description: IRG Working Documents Standards
;; Author: KAWABATA, Taichi <kawabata.taichi_at_gmail.com>
;; Version: 1.190510
;; Keywords: i18n languages tools
;; Human-Keywords: Ideographic Rapporteur Group
;; URL: https://github.com/kawabata/iwds

;;; Commentary:

;; This will produce the IWDS document series.

;;; Code:

(require 'bytecomp)
(require 'cl-lib)
(require 'dash)

(defvar iwds-directory (file-name-directory
                        (or byte-compile-current-file
                            load-file-name
                            buffer-file-name)))
(defvar iwds-xml-file)
  (setq iwds-xml-file (expand-file-name "iwds.xml" iwds-directory))
(defvar iwds-xml-data     nil)
(defvar iwds-id-table (make-hash-table :test 'equal))
(defvar iwds-ucv-html)
  (setq iwds-ucv-html (expand-file-name "ucv.html" iwds-directory))
(defvar iwds-nucv-html)
  (setq iwds-nucv-html (expand-file-name "nucv.html" iwds-directory))
(defvar iwds-ucv-summary-html)
  (setq iwds-ucv-summary-html (expand-file-name "ucv-summary.html" iwds-directory))
(defvar iwds-nucv-summary-html)
  (setq iwds-nucv-summary-html (expand-file-name "nucv-summary.html" iwds-directory))

(defvar iwds-main-buffer  nil)
(defvar iwds-toc-buffer   nil)
(defvar iwds-regexp       nil)
(defvar iwds-proc-funcs   nil)
(defvar iwds-proc-func-list
  '((ucv . ((group . iwds-proc-ucv-group)
            (subgroup . iwds-proc-ucv-group)
            (entry . iwds-proc-ucv-entry)))
    (nucv . ((group . iwds-proc-nothing)
            (subgroup . iwds-proc-nothing)
            (entry . iwds-proc-ucv-entry)))
    (ucv-summary . ((group . iwds-proc-ucv-summary-group)
                    (subgroup . iwds-proc-ucv-summary-group)
                    (entry . iwds-proc-ucv-summary-entry)))
    (nucv-summary . ((group . iwds-proc-nothing)
                     (subgroup . iwds-proc-nothing)
                     (entry . iwds-proc-ucv-summary-entry)))))
(defvar iwds-image-size-factor 9)
(defvar iwds-image-size-table nil)

;;; Main
(defun iwds-generate-files ()
  "Generate Various files."
  (interactive)
  (iwds-parse-xml-file)
  (iwds-image-size-table)
  (iwds-generate-file iwds-ucv-html 'ucv "^unifiable$")
  (iwds-generate-file iwds-nucv-html 'nucv "^not-unifiable$")
  (iwds-generate-file iwds-ucv-summary-html 'ucv-summary "^unifiable$")
  (iwds-generate-file iwds-nucv-summary-html 'nucv-summary "^not-unifiable$")
  )

(defun iwds-parse-xml-file ()
  "Load UCV XML Data of `iwds-xml-file'."
  (setq iwds-xml-data (cl-cdddar (xml-parse-file iwds-xml-file))))

(defun iwds-image-size-table ()
  "Obtain image file size of directories."
  (setq iwds-image-size-table (make-hash-table :test 'equal))
  (dolist (dir (list "supercjk" "ucs2003" "ucs2014" "ucs2017"))
    (with-temp-buffer
      (let ((dir (expand-file-name dir iwds-directory)))
        (cd dir)
        (if (/= (shell-command "identify *.png" (current-buffer)) 0)
            (message "Warning! No image file found at %s" dir)
          (goto-char (point-min))
          (while (re-search-forward "^\\(.+?\\.png\\).*x\\([0-9]+\\)" nil t)
            (puthash (expand-file-name (match-string 1) dir)
                     (string-to-number (match-string 2))
                     iwds-image-size-table)))))))

(defun iwds-generate-file (file func-set regexp)
  "Generate FILE by FUNC-SET and REGEXP."
  (when iwds-main-buffer (kill-buffer iwds-main-buffer))
  (when iwds-toc-buffer  (kill-buffer iwds-toc-buffer))
  (setq iwds-main-buffer (generate-new-buffer "*Main*")
        iwds-toc-buffer  (generate-new-buffer "*Toc*"))
  (setq iwds-regexp regexp)
  (setq iwds-proc-funcs (assoc-default func-set iwds-proc-func-list))
  (iwds-proc-xml iwds-xml-data)
  (with-temp-file file
    (insert-file-contents (concat file ".template"))
    (when (search-forward "<!--date-->" nil t)
      (replace-match (format-time-string "Version: %b/%d/%Y")))
    (when (search-forward "<!--toc-->\n" nil t)
      (insert (with-current-buffer iwds-toc-buffer (buffer-string))))
    (search-forward "<!--main-->\n")
    (insert (with-current-buffer iwds-main-buffer (buffer-string)))))

(defun iwds-proc-xml (xml-data)
  "Generate contents in `iwds-toc-buffer' and `iwds-main-buffer' for XML-DATA."
  (dolist (xml xml-data)
    (if (listp xml)
        (funcall (assoc-default (car xml) iwds-proc-funcs) xml))))

(defun iwds-proc-ucv-group (xml)
  "Process 'group' element of XML."
  (let* ((attrs (cadr xml))
         (id (assoc-default 'id attrs))
         (en (assoc-default 'en attrs)))
    (with-current-buffer iwds-toc-buffer
      (insert "
  <li><a href='#" id "'>" en "</a></li>"))
    (with-current-buffer iwds-main-buffer
      (insert (format "
  <tr>
    <td colspan='3'>
      <div id='%s'><h3>%s</h3></div>
    </td>
  </tr>" id en)))
    (iwds-proc-xml (cddr xml))))

(defun iwds-proc-ucv-entry (xml)
  "Process 'entry' element of XML."
  (let* ((attrs (cadr xml))
         (id (assoc-default 'id attrs))
         (kind (assoc-default 'kind attrs))
         (entry (iwds-proc-entry (cddr xml)))
         compatibles-chars-list)
    (when (string-match iwds-regexp kind)
    (with-current-buffer iwds-main-buffer
      (insert (format "
  <tr id='%s'>
    <td>%s</td>
    <td>" id id))
      (dolist (glyph (assoc-default :glyphs entry))
        (insert (format "
      <img height='26' width='26' src='./glyphs/%s.png'/>" glyph)))
      (insert "
    </td>
    <td>")
      (-when-let (jis (assoc-default :jis entry))
        (dolist (item (split-string jis ","))
          (insert "
      <img src='fig/jis." item ".gif' alt='jis." item "'/> (JIS X 0213 - " item ")<br/>")))
      (-when-let (hydcd (assoc-default :hydcd entry)) (insert "
      <img src='fig/xinjiu" hydcd ".png' alt='hydcd." hydcd "'/> (HYDCD - " hydcd ")<br/>"))
      (-when-let (scs-chars-list (assoc-default :scs entry))
        (insert "
      <hr widh='90%' size='4'/>
      <h3>Source Code Separations</h3>")
        (iwds-proc-ucv-chars-list scs-chars-list))
      (-when-let (disunified-chars-list (assoc-default :disunified entry))
        (insert "
      <hr widh='90%' size='4'/>
      <h3>Disunified Ideographs</h3>")
        (iwds-proc-ucv-chars-list disunified-chars-list))
      (when (setq compatibles-chars-list (assoc-default :compatibles entry))
        (insert "
      <hr widh='90%' size=4/>
      <h3>Compatibility Ideographs</h3>")
        (iwds-proc-ucv-chars-list compatibles-chars-list))
      (-when-let (unified-chars (assoc-default :unified entry))
        (insert "
      <hr widh='90%' size=4/>")
        (if (memq ?… unified-chars) (insert "
      <h3>Unified Ideographs (Examples)</h3>")
          (insert "
      <h3>Unified Ideographs</h3>"))
        (iwds-proc-ucv-chars-list
         (mapcar 'list (remove ?… unified-chars))))
      (-when-let (note (assoc-default :note entry))
        (insert "
      <hr width='90%' size=4/>
      <h4>Note</h4>"
                note))
      (-when-let (url (assoc-default :ReviewSystem entry))
        (insert "
      <hr width='90%' size=4/>
      <h4>Review System</h4>
      <a href='" url "'>" url "</a>"))
      (insert "
    </td>
  </tr>")))))

(defun iwds-proc-ucv-summary-group (xml)
  "Process 'group' element of XML for UCV summary."
  (let* ((attrs (cadr xml))
         (id (assoc-default 'id attrs))
         (en (assoc-default 'en attrs)))
    (with-current-buffer iwds-toc-buffer
      (insert "
  <li><a href='#" id "'>" en "</a></li>"))
    (with-current-buffer iwds-main-buffer
      (insert (format "
  </div>
  <div id='%s'><h3>%s</h3></div>
  <div class='multicol'>
"
                      id en)))
    (iwds-proc-xml (cddr xml))))

(defun iwds-proc-ucv-summary-entry (xml)
  "Process 'entry' element of XML."
  (let* ((attrs (cadr xml))
         (id (assoc-default 'id attrs))
         (kind (assoc-default 'kind attrs))
         (entry (iwds-proc-entry (cddr xml))))
    (when (string-match iwds-regexp kind)
    (with-current-buffer iwds-main-buffer
      (insert (format "
  <table><tr id='%s'>
    <td>%s</td>
    <td>" id id))
      (dolist (glyph (assoc-default :glyphs entry))
        (insert (format "
      <img height='26' width='26' src='./glyphs/%s.png'/>" glyph)))
      (insert "
    </td>
    <td>")
      (-when-let (unified-chars (assoc-default :unified entry))
        (apply 'insert (mapcar (lambda (char) (if (characterp char) char (cdr char)))
                               unified-chars)))
      (insert "
    </td>
  </tr></table>")))))

(defun iwds-proc-entry (xml-data)
  "Create entry data from XML-DATA."
  (cl-labels ((\,. (key) (cl-caddr (assoc key xml-data))))
    `((:glyphs .
       ,(split-string ,.'glyphs "," t))
      (:components . ,(iwds-parse-chars ,.'components))
      (:compatibles
       ;; ((<unified ideograph>  <compatibility ideograph>)....)
       .,(mapcar
          (lambda (char)
            (let* ((decomp
                    (car
                     (get-char-code-property (or (cdr-safe char) char) 'decomposition))))
              (list (if (consp char) (cons (car char) decomp) decomp)
                    char)))
          (iwds-parse-chars ,.'compatibles)))
      (:jis . ,,.'jis)
      (:hydcd . ,,.'hydcd)
      (:disunified . ,(iwds-parse-char-lists ,.'disunified))
      (:scs . ,(iwds-parse-char-lists ,.'SourceCodeSeparation))
      (:unified . ,(iwds-parse-chars ,.'unified))
      (:duplicates . ,(iwds-parse-char-lists ,.'duplicates))
      (:note . ,,.'note)
      (:ReviewSystem . ,,.'ReviewSystem)
      )))

(defun iwds-proc-ucv-chars-list (chars-list)
  "Output CHARS-LIST in HTML table format in current buffer."
  (insert "
      <table>")
  (dolist (chars chars-list)
    (insert "
        <tr>")
    (dolist (char chars)
      (let* ((file (cl-case (car-safe char)
                     (supercjk (format "./supercjk/%05X.png" (cdr char)))
                     (ucs2003  (format "./ucs2003/%05X.png" (cdr char)))
                     (ucs2014  (format "./ucs2014/%05X.png" (cdr char)))
                     (t        (format "./ucs2017/%05X.png" char))))
             (size (cl-case (car-safe char)
                     (supercjk 560)
                     (ucs2003  280)
                     (t (gethash (expand-file-name file iwds-directory) iwds-image-size-table)))))
        (unless size (message "Image not found! %s" file) (setq size 0))
        (insert (format "
          <td><div style='position:absolute; z-index:-1'>%c%05X</div>
              <img height='%d' src='%s' alt=''/></td>"
                        (if (consp char) (cdr char) char)
                        (if (consp char) (cdr char) char)
                        (/ size iwds-image-size-factor) file))))
    (insert "
        </tr>"))
  (insert "
      </table>"))

(defun iwds-parse-char-lists (string)
  "Parse character list in STRING."
  (when string
    (mapcar
     (lambda (chars) (iwds-parse-chars chars))
     (split-string string "," t))))

(defun iwds-parse-chars (string)
  "Parse characters in STRING."
  (when string
    (if (string-match "[*#$]" string)
        (with-temp-buffer
          (let (result)
            (insert string)
            (goto-char (point-min))
            (while (re-search-forward ".\\([*#$]\\)?" nil t)
              (push
               (pcase (char-after (match-beginning 1))
                 (`?$ (cons 'ucs2014 (char-after (match-beginning 0))))
                 (`?* (cons 'ucs2003 (char-after (match-beginning 0))))
                 (`?# (cons 'supercjk (char-after (match-beginning 0))))
                 (_ (char-after (match-beginning 0))))
               result))
            (nreverse result)))
      (string-to-list string))))

(defun iwds-proc-nothing (xml)
  (iwds-proc-xml (cddr xml)))

(when noninteractive (iwds-generate-files))

(provide 'iwds)

;; Local Variables:
;; outline-minor-mode: t
;; time-stamp-pattern: "10/Version:\\\\?[ \t]+1.%02y%02m%02d\\\\?\n"
;; eval: (hide-sublevels 5)
;; End:

;;; iwds.el ends here
