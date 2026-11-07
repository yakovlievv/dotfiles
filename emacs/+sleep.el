;;; +sleep.el --- the night's sleep: planned, clocked, logged -*- lexical-binding: t; -*-

;; Sleep scheduling (roam note f7671870-2e52-4386-8d78-47ee117e7069):
;; the vault plans each night, Home Assistant follows the plan, and the
;; phone and Emacs clock the night in and out through vault-api.
;;
;; - The default night is one heading with an :ID: (`+sleep-source-id') in
;;   the sleep optimization system note, with a repeating range like
;;   <2026-11-08 Sun 01:00-09:00 +1d> and a :SKIP: like a habit's.
;; - The night of bed-day D (the org day, which lasts until
;;   `org-extend-today-until') is called D everywhere. Its times fall on
;;   the occurrence date: D+1 when bedtime is before that hour, else D.
;;   :SKIP: holds occurrence dates.
;; - Each night gets a copy: a `Sleep' heading with no TODO keyword, a child
;;   of day D (next to its DO list, never inside it), or a top-level heading
;;   of the upcoming note while day D has no note. Properties :ID:,
;;   :SLEEP_ID: (the source), :NIGHT: (D), :AREA: sleep, :CALDAV_UID:; the
;;   body line is a plain active stamp with the planned range. Making a copy
;;   puts the default's occurrence into the source's :SKIP:, so from then on
;;   only the copy shows. Skipped with no copy: no sleep planned, no alarm.
;;
;; Loads after `+endgame-capture.el', whose helpers it uses. The functions
;; the server calls through emacsclient (`+sleep-*-json') ask nothing,
;; save what they change and return JSON with the saved files.

(require 'cl-lib)
(require 'json)
(require 'subr-x)
(require 'org)
(require 'org-clock)

(defvar org-journal-dir)
(declare-function org-journal--get-entry-path "org-journal")
(declare-function +repeat-skip-add "config")
(declare-function +repeat-skipped-p "config")
(declare-function +habits--shift-levels "config")

;;; Where things live

(defvar +sleep-source-id "1b479cff-5a96-4996-b7a7-1086ae8b6f52"
  "The :ID: of the default night, `Sleep schedule' in the sleep optimization system note.")

(defvar +sleep-area "sleep"
  "The AREA_TAG a night's copy carries as :AREA:.")

(defvar +sleep-title "Sleep"
  "The heading of a night's copy.")

;;; Dates

(defun +sleep--day-end-hour ()
  "The hour org's day ends at: `org-extend-today-until'."
  org-extend-today-until)

(defun +sleep--add-days (date n)
  "DATE (\"YYYY-MM-DD\") plus N days, as \"YYYY-MM-DD\"."
  (let ((d (calendar-gregorian-from-absolute (+ (org-time-string-to-absolute date) n))))
    (format "%04d-%02d-%02d" (nth 2 d) (nth 0 d) (nth 1 d))))

(defun +sleep--minutes (hhmm)
  "Minutes after midnight of the \"HH:MM\" (or \"H:MM\") HHMM."
  (pcase-let ((`(,h ,m) (mapcar #'string-to-number (split-string hhmm ":"))))
    (+ (* 60 h) m)))

(defun +sleep--time (date hhmm)
  "DATE (\"YYYY-MM-DD\") at HHMM as an Emacs time."
  (pcase-let ((`(,y ,mo ,d) (mapcar #'string-to-number (split-string date "-")))
              (`(,h ,mi) (mapcar #'string-to-number (split-string hhmm ":"))))
    (encode-time 0 mi h d mo y)))

(defun +sleep-night-of-time (time)
  "The night (\"YYYY-MM-DD\", the org day) TIME belongs to.
Before `org-extend-today-until' it is still the day before."
  (let* ((dt (decode-time time))
         (abs (calendar-absolute-from-gregorian
               (list (decoded-time-month dt) (decoded-time-day dt) (decoded-time-year dt))))
         (d (calendar-gregorian-from-absolute
             (if (< (decoded-time-hour dt) (+sleep--day-end-hour)) (1- abs) abs))))
    (format "%04d-%02d-%02d" (nth 2 d) (nth 0 d) (nth 1 d))))

;;; The default night

(defun +sleep--source ()
  "Marker at the default night's heading (`+sleep-source-id')."
  (or (let ((m (ignore-errors (org-id-find +sleep-source-id t))))
        (and (markerp m) m))
      ;; `org-id-find' can miss a note the daemon never scanned and the
      ;; fallback rg skips: look in the vault directly
      (cl-some (lambda (f) (+endgame--find-id (+endgame--buffer f) +sleep-source-id))
               (+endgame--rg-files (concat "^\\s*:ID:\\s+" (regexp-quote +sleep-source-id) "\\s*$")
                                   (list +endgame-vault-dir)))
      (error "No Sleep schedule heading with ID %s" +sleep-source-id)))

(defun +sleep--source-range ()
  "(START END) of the default night, \"HH:MM\" each."
  (let* ((src (+sleep--source))
         (range (or (+endgame-entry-time-range src)
                    (error "The Sleep schedule heading has no timestamp"))))
    (unless (and (nth 1 range) (nth 2 range))
      (error "The Sleep schedule stamp needs a time range, like 01:00-09:00"))
    (list (nth 1 range) (nth 2 range))))

(defun +sleep-occurrence-date (night &optional start)
  "The date NIGHT's times fall on, \"YYYY-MM-DD\".
NIGHT is \"YYYY-MM-DD\"; START (\"HH:MM\", default the source's bedtime)
before the hour the day ends at is on the next date."
  (let ((start (or start (car (+sleep--source-range)))))
    (if (< (+sleep--minutes start) (* 60 (+sleep--day-end-hour)))
        (+sleep--add-days night 1)
      night)))

(defun +sleep-skipped-p (night)
  "Non-nil when NIGHT's default occurrence is in the source's :SKIP:."
  (+repeat-skipped-p (+sleep-occurrence-date night) (+sleep--source)))

;;; A night's copy

(defun +sleep--stamp (night start end)
  "The plain active stamp of NIGHT from START to END (\"HH:MM\").
One date: <D 01:00-09:00>; across midnight: <D 23:30>--<D+1 08:00>."
  (let* ((date (+sleep-occurrence-date night start))
         (end-date (if (<= (+sleep--minutes end) (+sleep--minutes start))
                       (+sleep--add-days date 1)
                     date)))
    (if (equal date end-date)
        (+endgame--format-stamp (+sleep--time date start) t end)
      (concat (+endgame--format-stamp (+sleep--time date start) t)
              "--"
              (+endgame--format-stamp (+sleep--time end-date end) t)))))

(defun +sleep--copy-at (pos)
  "Non-nil when the heading at POS is a copy of the default night."
  (equal (org-entry-get pos "SLEEP_ID") +sleep-source-id))

(defun +sleep--copy-in (buffer night &optional bound-marker)
  "Marker at NIGHT's copy in BUFFER, or nil.
BOUND-MARKER: only inside the subtree at that marker."
  (with-current-buffer buffer
    (org-with-wide-buffer
     (let ((beg (if bound-marker (marker-position bound-marker) (point-min)))
           (end (if bound-marker
                    (save-excursion (goto-char bound-marker) (org-end-of-subtree t t) (point))
                  (point-max)))
           found)
       (goto-char beg)
       (while (and (not found)
                   (re-search-forward (format "^[ \t]*:NIGHT:[ \t]+%s[ \t]*$" (regexp-quote night)) end t))
         (save-excursion
           (when (and (ignore-errors (org-back-to-heading t) t)
                      (+sleep--copy-at (point)))
             (setq found (point-marker)))))
       found))))

(defun +sleep-copy (night)
  "Marker at NIGHT's copy, in day NIGHT's note or in upcoming, or nil.
A copy is found by its :NIGHT: and :SLEEP_ID:."
  (or (when-let ((day (+endgame--day-marker night)))
        (+sleep--copy-in (marker-buffer day) night day))
      (when (file-exists-p +endgame-upcoming-file)
        (+sleep--copy-in (+endgame--buffer +endgame-upcoming-file) night))))

(defun +sleep--copy-text (night stamp)
  "A fresh copy of NIGHT at STAMP, as a level 1 heading."
  (concat "* " +sleep-title "\n"
          ":PROPERTIES:\n"
          ":ID:       " (org-id-uuid) "\n"
          ":SLEEP_ID: " +sleep-source-id "\n"
          ":NIGHT:    " night "\n"
          ":AREA:     " +sleep-area "\n"
          ":CALDAV_UID: " (+endgame--uid) "\n"
          ":END:\n"
          stamp "\n"))

(defun +sleep--append-to-day (day text)
  "Append TEXT (an org subtree) as a child of the journal DAY (a marker), last."
  (with-current-buffer (marker-buffer day)
    (org-with-wide-buffer
     (goto-char day)
     (let ((level (org-current-level)))
       (org-end-of-subtree t t)
       (unless (bolp) (insert "\n"))
       (insert (string-trim-right
                (+habits--shift-levels text (- (1+ level) (+endgame--text-level text))))
               "\n")))))

(defun +sleep--retime (copy stamp)
  "Replace the plain stamp of the COPY (a marker) by STAMP."
  (org-with-point-at copy
    (org-with-wide-buffer
     (let ((old (+endgame-entry-stamp)))
       (org-back-to-heading t)
       (if (and old (re-search-forward (regexp-quote old) (save-excursion (outline-next-heading) (point)) t))
           (replace-match stamp t t)
         (org-end-of-meta-data t)
         (insert stamp "\n"))))))

(defun +sleep-plan (night &optional start end)
  "Plan NIGHT (\"YYYY-MM-DD\"); return a marker at its copy.
START and END (\"HH:MM\") are bedtime and wake, the source's by default.
The default's occurrence goes into the source's :SKIP:. An existing copy
is retimed in place when START is given, else left as it is. A new copy
goes into day NIGHT's note as its last child, or into upcoming when that
day has no note yet (making the day moves it in). Asks nothing; the
caller saves."
  (let* ((src (+sleep--source))
         (default (+sleep--source-range))
         (retime start)
         (start (or start (car default)))
         (end (or end (nth 1 default)))
         (stamp (+sleep--stamp night start end)))
    (org-with-point-at src
      (org-with-wide-buffer
       (+repeat-skip-add (+sleep-occurrence-date night (car default)))))
    (let ((copy (+sleep-copy night)))
      (cond
       (copy
        (when retime (+sleep--retime copy stamp))
        copy)
       (t
        (let* ((text (+sleep--copy-text night stamp))
               (id (and (string-match "^:ID: +\\(\\S-+\\)" text) (match-string 1 text)))
               (day (+endgame--day-marker night)))
          (if day
              (+sleep--append-to-day day text)
            (+endgame--append-to-upcoming text))
          (or (+endgame--find-id (if day (marker-buffer day) (+endgame--buffer +endgame-upcoming-file)) id)
              (error "Lost the Sleep copy of %s" night))))))))

(defun +sleep--result (m)
  "{file, line, id} of the heading at marker M, as an alist."
  `((file . ,(buffer-file-name (marker-buffer m)))
    (line . ,(with-current-buffer (marker-buffer m)
               (org-with-wide-buffer (line-number-at-pos m))))
    (id . ,(org-entry-get m "ID"))))

(defun +sleep--files ()
  "The files saved in the innermost `+endgame--saving', relative, as a vector."
  (vconcat (mapcar #'+endgame--relative (reverse +endgame--saved))))

(defun +sleep-plan-json (night &optional start end)
  "`+sleep-plan' for the server: asks nothing, saves, returns JSON
{\"file\", \"line\", \"id\", \"where\": \"day\"|\"upcoming\", \"files\"}."
  (let ((inhibit-interaction t)
        (+endgame--saved nil)
        result)
    (+endgame--saving
      (let ((m (+sleep-plan night start end)))
        (setq result
              (append (+sleep--result m)
                      `((where . ,(if (file-equal-p (buffer-file-name (marker-buffer m))
                                                    +endgame-upcoming-file)
                                      "upcoming" "day")))))))
    (+endgame--json (append result `((files . ,(+sleep--files)))))))

(provide '+sleep)
;;; +sleep.el ends here
