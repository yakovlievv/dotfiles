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
(declare-function +repeat-skip-dates "config")
(declare-function +org-journal/set-morning-log "config")

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
  "Marker at the default night's heading (`+sleep-source-id').
Through `+endgame--buffer': the note is written by vault-api and
Syncthing too, so a buffer that went stale is re-read first."
  (let ((in (lambda (file)
              (and file (file-exists-p file)
                   (+endgame--find-id (+endgame--buffer file) +sleep-source-id)))))
    (or (funcall in (ignore-errors (org-id-find-id-file +sleep-source-id)))
        ;; a note the id cache doesn't know (or has wrong): ask the vault
        (funcall in (car (+endgame--rg-files
                          (concat "^\\s*:ID:\\s+" (regexp-quote +sleep-source-id) "\\s*$")
                          (list +endgame-vault-dir))))
        (error "No Sleep schedule heading with ID %s" +sleep-source-id))))

(defun +sleep--hhmm (hhmm)
  "HHMM (\"H:MM\" or \"HH:MM\") as \"HH:MM\"; an error when it isn't a time of day."
  (unless (and (stringp hhmm) (string-match "\\`\\([0-9]\\{1,2\\}\\):\\([0-9]\\{2\\}\\)\\'" hhmm))
    (error "Not a time of day (HH:MM): %S" hhmm))
  (let ((h (string-to-number (match-string 1 hhmm)))
        (m (string-to-number (match-string 2 hhmm))))
    (unless (and (< h 24) (< m 60))
      (error "Not a time of day (HH:MM): %S" hhmm))
    (format "%02d:%02d" h m)))

(defun +sleep--check-night (night)
  "NIGHT, or an error when it isn't \"YYYY-MM-DD\"."
  (unless (and (stringp night) (string-match-p "\\`[0-9]\\{4\\}-[0-9]\\{2\\}-[0-9]\\{2\\}\\'" night))
    (error "Not a night (YYYY-MM-DD): %S" night))
  night)

(defvar +sleep-skip-keep-days 7
  "Dates in the source's :SKIP: older than this many days before today go.
Every night's copy adds one, and the source has no SCHEDULED to prune by.")

(defun +sleep--skip-add (src date)
  "Add DATE to the :SKIP: of the source at SRC, dropping long-past dates."
  (org-with-point-at src
    (org-with-wide-buffer
     (+repeat-skip-add date)
     (let* ((cut (+sleep--add-days (+endgame--today) (- +sleep-skip-keep-days)))
            (dates (+repeat-skip-dates))
            (keep (seq-remove (lambda (d) (string< d cut)) dates)))
       (unless (equal keep dates)
         (if keep
             (org-entry-put nil "SKIP" (string-join keep " "))
           (org-entry-delete nil "SKIP")))))))

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
      (when (or (find-buffer-visiting +endgame-upcoming-file)
                (file-exists-p +endgame-upcoming-file))
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
is retimed in place when START or END is given, else left as it is. A new copy
goes into day NIGHT's note as a child right after its DO list, or into
upcoming when that day has no note yet (making the day moves it in). Asks nothing; the
caller saves."
  (+sleep--check-night night)
  (let* ((src (+sleep--source))
         (default (+sleep--source-range))
         (retime (or start end))
         (start (+sleep--hhmm (or start (car default))))
         (end (+sleep--hhmm (or end (nth 1 default))))
         (stamp (+sleep--stamp night start end)))
    (+sleep--skip-add src (+sleep-occurrence-date night (car default)))
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
              (+endgame--append-to-day day (list text))
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

;;; Day making, last night, the morning

(defun +sleep-ensure-night (night)
  "Marker at NIGHT's copy, made from the default when missing.
Nil when NIGHT is skipped and has no copy: no sleep planned. Making day
NIGHT calls this after the staging move, so a copy planned ahead in
upcoming is the one that stays."
  (or (+sleep-copy night)
      (unless (+sleep-skipped-p night)
        (+sleep-plan night))))

(defconst +sleep--closed-clock-re
  "^[ \t]*CLOCK: \\[[^]\n]*\\]--\\[[^]\n]*\\]"
  "A closed CLOCK line.")

(defun +sleep--entry-end (pom)
  "End of the entry at POM's own text, before its first child."
  (org-with-point-at pom
    (org-with-wide-buffer
     (org-back-to-heading t)
     (save-excursion (outline-next-heading) (point)))))

(defun +sleep-night-logged-p (night)
  "Non-nil when NIGHT's copy has a closed CLOCK line."
  (when-let ((copy (+sleep-copy night)))
    (org-with-point-at copy
      (org-with-wide-buffer
       (re-search-forward +sleep--closed-clock-re (+sleep--entry-end copy) t)))))

(defun +sleep--clock-stamp (time)
  "TIME as a clock line's inactive stamp, [YYYY-MM-DD Day HH:MM]."
  (format-time-string (org-time-stamp-format t t) time))

(defun +sleep--clock-minutes (start end)
  "Whole minutes from START to END, both cut to the minute, at least 0."
  (let ((m (lambda (time) (floor (float-time time) 60))))
    (max 0 (- (funcall m end) (funcall m start)))))

(defun +sleep--duration (minutes)
  "MINUTES as a clock line's duration, the way `org-clock-out' writes it."
  (format "%2d:%02d" (/ minutes 60) (% minutes 60)))

(defun +sleep--clock-line (start &optional end)
  "A CLOCK line from START, closed at END when given (Emacs times)."
  (concat "CLOCK: " (+sleep--clock-stamp start)
          (when end
            (concat "--" (+sleep--clock-stamp end)
                    " => " (+sleep--duration (+sleep--clock-minutes start end))))))

(defun +sleep--insert-clock (pom line)
  "Insert the CLOCK LINE (text) in the :LOGBOOK: of the entry at POM.
Where `org-clock-in' would put it (`org-clock-find-position')."
  (org-with-point-at pom
    (org-with-wide-buffer
     (org-back-to-heading t)
     (org-clock-find-position nil)
     (unless (bolp) (insert "\n"))
     (insert-before-markers line "\n"))))

(defun +sleep-log-night (night bed wake)
  "Write a closed CLOCK line BED--WAKE on NIGHT's copy; return a marker at it.
BED and WAKE are read as `org-read-date' reads them (\"2026-11-04
23:30\"). The copy is made (`+sleep-plan') when NIGHT has none, a skipped
night too: it was slept. Asks nothing; the caller saves."
  (+sleep--check-night night)
  (let ((b (org-read-date t t bed))
        (w (org-read-date t t wake)))
    (unless (time-less-p b w)
      (error "Bed time %s isn't before wake time %s" bed wake))
    (let ((copy (or (+sleep-copy night) (+sleep-plan night))))
      (+sleep--insert-clock copy (+sleep--clock-line b w))
      copy)))

(defun +sleep-put-morning (night morning)
  "Write the morning log on NIGHT's copy; return a marker at it.
MORNING is (HEADACHE FRESHNESS MOOD NOTES): the scores (1-10) become
:MORNING_HEADACHE:, :MORNING_FRESHNESS:, :MORNING_MOOD:, NOTES (when not
empty) plain text at the end of the copy's body. The copy is made when
missing. Asks nothing; the caller saves."
  (+sleep--check-night night)
  (let ((scores
         (cl-loop for score in (seq-take morning 3)
                  for prop in '("MORNING_HEADACHE" "MORNING_FRESHNESS" "MORNING_MOOD")
                  collect (let ((n (if (stringp score) (string-to-number score) score)))
                            (unless (and (integerp n) (<= 1 n 10))
                              (error "%s must be 1-10, not %S" prop score))
                            (cons prop n))))
        (notes (string-trim (or (nth 3 morning) ""))))
    (unless (= (length scores) 3)
      (error "The morning log needs three scores, not %S" morning))
    (let ((copy (or (+sleep-copy night) (+sleep-plan night))))
      (pcase-dolist (`(,prop . ,n) scores)
        (org-entry-put copy prop (number-to-string n)))
      (unless (string-empty-p notes)
        (with-current-buffer (marker-buffer copy)
          (org-with-wide-buffer
           (goto-char (+sleep--entry-end copy))
           (skip-chars-backward " \t\n")
           (forward-line 1)
           (unless (bolp) (insert "\n"))
           (insert notes "\n"))))
      copy)))

(defun +sleep--read-night (night)
  "Ask NIGHT's bed and wake times; (BED WAKE) as \"YYYY-MM-DD HH:MM\".
A bare time is on NIGHT's date, except a bed time before the hour the
day ends at, which is after midnight: the next date. A wake time not
after bed is on the day after."
  (let* ((org-read-date-prefer-future nil)
         (bed (org-read-date t t nil "Bed time (last night)" (+sleep--time night "12:00")))
         (bed (if (and (equal (+endgame--date bed) night)
                       (< (decoded-time-hour (decode-time bed)) (+sleep--day-end-hour)))
                  (time-add bed (days-to-time 1))
                bed))
         (wake (org-read-date t t nil "Wake time" bed))
         (wake (if (time-less-p bed wake) wake (time-add wake (days-to-time 1)))))
    (list (format-time-string "%Y-%m-%d %H:%M" bed)
          (format-time-string "%Y-%m-%d %H:%M" wake))))

(defun +sleep-day-prompts (day)
  "The questions making DAY (a time) by hand asks, from `+org-journal-init-day'.
\"Log last night?\" only when last night (the night before DAY) has no
closed sleep clock (a night away, a forgotten clock-in): the bed and wake
answers become its CLOCK line. \"Log morning?\": the morning log, on last
night's Sleep heading (`+org-journal/set-morning-log')."
  (when day
    (let ((night (+sleep--add-days (+endgame--date day) -1)))
      (when (and (not (+sleep-night-logged-p night))
                 (y-or-n-p "Log last night? "))
        (apply #'+sleep-log-night night (+sleep--read-night night)))
      (when (y-or-n-p "Log morning? ")
        (+org-journal/set-morning-log night)))))

(provide '+sleep)
;;; +sleep.el ends here
