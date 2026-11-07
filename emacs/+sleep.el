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
  "Add DATE to the :SKIP: of the source at SRC, dropping long-past dates.
Dates older than `+sleep-skip-keep-days' before today go, and the
source's stamp moves forward to that cut (time range and repeater
kept), so the dropped nights can't show up again, the way a habit's
SCHEDULED moves on."
  (org-with-point-at src
    (org-with-wide-buffer
     (+repeat-skip-add date)
     (let* ((cut (+sleep--add-days (+endgame--today) (- +sleep-skip-keep-days)))
            (dates (+repeat-skip-dates))
            (keep (seq-remove (lambda (d) (string< d cut)) dates))
            (stamp (+endgame-entry-stamp)))
       (unless (equal keep dates)
         (when (and stamp (string-match "\\`<\\([0-9-]\\{10\\}\\) [^ >]+" stamp)
                    (string< (match-string 1 stamp) cut))
           (let* ((rest (substring stamp (match-end 0)))
                  (new (concat "<" cut " " (format-time-string "%a" (+endgame--date-time cut)) rest)))
             (save-excursion
               (org-back-to-heading t)
               (when (search-forward stamp (save-excursion (outline-next-heading) (point)) t)
                 (replace-match new t t)))))
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

(defun +sleep--copy-text (id night stamp)
  "A fresh copy of NIGHT at STAMP with :ID: ID, as a level 1 heading."
  (concat "* " +sleep-title "\n"
          ":PROPERTIES:\n"
          ":ID:       " id "\n"
          ":SLEEP_ID: " +sleep-source-id "\n"
          ":NIGHT:    " night "\n"
          ":AREA:     " +sleep-area "\n"
          ":CALDAV_UID: " (+endgame--uid) "\n"
          ":END:\n"
          stamp "\n"))

(defun +sleep--inactive-stamp (pom)
  "The first inactive stamp (or range) in the body of the entry at POM, or nil.
A copy whose event was deleted on the phone has its stamp made inactive:
that night has no sleep planned. CLOCK, planning and property lines
don't count."
  (org-with-point-at pom
    (org-with-wide-buffer
     (org-back-to-heading t)
     (let ((end (save-excursion (outline-next-heading) (point)))
           (re (concat org-ts-regexp-inactive "\\(?:--" org-ts-regexp-inactive "\\)?"))
           found)
       (forward-line 1)
       (while (and (not found) (re-search-forward re end t))
         (unless (save-excursion
                   (beginning-of-line)
                   (looking-at-p (concat "[ \t]*\\(?:CLOCK:\\|" org-keyword-time-regexp "\\|:[^ \t\n]+:\\)")))
           (setq found (match-string-no-properties 0))))
       found))))

(defun +sleep-cancelled-p (copy)
  "Non-nil when COPY (a marker) has no active stamp: its night has no sleep planned."
  (not (+endgame-entry-stamp copy)))

(defun +sleep--retime (copy stamp)
  "Replace the plain stamp of the COPY (a marker) by STAMP.
An inactive one (the night was cancelled) is replaced too: planned again."
  (org-with-point-at copy
    (org-with-wide-buffer
     (let ((old (or (+endgame-entry-stamp) (+sleep--inactive-stamp (point))))
           (end (save-excursion (outline-next-heading) (point)))
           done)
       (org-back-to-heading t)
       ;; the stamp's own line: a logged night's CLOCK line can read the same
       (while (and old (not done) (re-search-forward (regexp-quote old) end t))
         (unless (save-excursion (beginning-of-line) (looking-at-p "[ \t]*CLOCK:"))
           (replace-match stamp t t)
           (setq done t)))
       (unless done
         (org-back-to-heading t)
         (org-end-of-meta-data t)
         (insert stamp "\n"))))))

(defun +sleep-plan (night &optional start end)
  "Plan NIGHT (\"YYYY-MM-DD\"); return a marker at its copy.
START and END (\"HH:MM\") are bedtime and wake, the source's by default.
The default's occurrence goes into the source's :SKIP:. An existing copy
is retimed in place when START or END is given, else left as it is; one
whose stamp was made inactive (the night cancelled on the phone) gets an
active stamp again, with these times. A new copy
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
        (when (or retime (+sleep-cancelled-p copy))
          (+sleep--retime copy stamp))
        copy)
       (t
        (let* ((id (org-id-uuid))
               (text (+sleep--copy-text id night stamp))
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
night too: it was slept. An open clock on the copy (clocked in, never
out) becomes this line; the same line twice is written once, so the
phone may send it again. A night that already has a closed clock (clocked
in and out from the phone or Emacs) is left as it is: answering \"Log last
night?\" on top of that would log the night twice. Asks nothing; the
caller saves."
  (+sleep--check-night night)
  (let ((b (org-read-date t t bed))
        (w (org-read-date t t wake)))
    (unless (time-less-p b w)
      (error "Bed time %s isn't before wake time %s" bed wake))
    (let* ((copy (or (+sleep-copy night) (+sleep-plan night)))
           (line (+sleep--clock-line b w)))
      (org-with-point-at copy
        (org-with-wide-buffer
         (let ((end (+sleep--entry-end copy)))
           (cond
            ((save-excursion (search-forward line end t)))
            ((re-search-forward +sleep--open-clock-re end t)
             (replace-match (concat (match-string 1) line) t t))
            ((save-excursion (re-search-forward +sleep--closed-clock-re end t)))
            (t (+sleep--insert-clock copy line))))))
      copy)))

(defun +sleep-put-morning (night morning)
  "Write the morning log on NIGHT's copy; return a marker at it.
MORNING is (HEADACHE FRESHNESS MOOD NOTES): the scores (1-10) become
:MORNING_HEADACHE:, :MORNING_FRESHNESS:, :MORNING_MOOD:, NOTES (when not
empty) plain text at the end of the copy's body, once (the phone may
send it again). The copy is made when missing. Asks nothing; the caller
saves."
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
      ;; a line starting with * would be a heading
      (setq notes (replace-regexp-in-string "^\\*" " *" notes))
      (unless (or (string-empty-p notes)
                  (org-with-point-at copy
                    (org-with-wide-buffer
                     (search-forward (concat "\n" notes "\n") (+sleep--entry-end copy) t))))
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
        (let ((times (+sleep--read-night night)))
          ;; it may be another week's file, and the source's :SKIP:
          (+endgame--saving (apply #'+sleep-log-night night times))))
      (when (y-or-n-p "Log morning? ")
        (+org-journal/set-morning-log night)))))

;;; The server: clock in and out, the next night

(defconst +sleep--open-clock-re
  "^\\([ \t]*\\)CLOCK: \\(\\[[^]\n]*\\]\\)[ \t]*$"
  "An open CLOCK line: group 1 its indentation, 2 its start stamp.")

(defconst +sleep--open-clock-rg "^\\s*CLOCK: \\[[^]]*\\]\\s*$"
  "`+sleep--open-clock-re' for ripgrep.")

(defun +sleep--now (now)
  "NOW (an Emacs time, nil for the current time) cut to the minute."
  (let ((s (floor (float-time (or now (current-time))))))
    (seconds-to-time (- s (mod s 60)))))

(defun +sleep--files-with-open-clocks (paths)
  "Files under PATHS with an open CLOCK line, archives left out.
Files only changed in a buffer so far count too: ripgrep reads the disk."
  (seq-remove
   (lambda (f) (string-match-p "/archive/" f))
   (delete-dups
    (append (+endgame--rg-files +sleep--open-clock-rg paths)
            (cl-loop for buf in (buffer-list)
                     for f = (buffer-file-name buf)
                     when (and f (buffer-modified-p buf)
                               (string-suffix-p ".org" f)
                               (not (string-match-p "/\\(?:templates\\|config\\)/" f))
                               (cl-some (lambda (p) (file-in-directory-p f p)) paths))
                     collect f)))))

(defun +sleep--open-clocks (paths)
  "The open CLOCK lines in PATHS: a list of (MARKER START HEADING-MARKER).
MARKER is at the line's start, START the clock-in time."
  (let (out)
    (dolist (file (+sleep--files-with-open-clocks paths))
      (with-current-buffer (+endgame--buffer file)
        (org-with-wide-buffer
         (goto-char (point-min))
         (while (re-search-forward +sleep--open-clock-re nil t)
           (let ((start (org-time-string-to-time (match-string 2)))
                 (line (copy-marker (line-beginning-position))))
             ;; a real clock, not one shown in an example or src block
             (when (save-excursion
                     (goto-char line)
                     (skip-chars-forward " \t")
                     (eq (org-element-type (org-element-at-point)) 'clock))
               (push (list line start
                           (save-excursion
                             (and (ignore-errors (org-back-to-heading t) t) (point-marker))))
                     out)))))))
    (nreverse out)))

(defun +sleep--close-clock (line start end)
  "Close the open CLOCK line at marker LINE (started at START) at END.
Returns the minutes."
  (with-current-buffer (marker-buffer line)
    (org-with-wide-buffer
     (goto-char line)
     (unless (looking-at +sleep--open-clock-re)
       (error "No open clock at %s:%d" (buffer-file-name) (line-number-at-pos)))
     (let ((indent (match-string 1)))
       (replace-match (concat indent (+sleep--clock-line start end)) t t))
     (+sleep--clock-minutes start end))))

(defun +sleep--open-sleep-clocks ()
  "The open clocks on Sleep copies: (NIGHT MARKER START COPY-MARKER), latest night first."
  (sort (cl-loop for (line start heading) in (+sleep--open-clocks
                                              (list (expand-file-name org-journal-dir)
                                                    +endgame-upcoming-file))
                 when (and heading (+sleep--copy-at heading))
                 collect (list (org-entry-get heading "NIGHT") line start heading))
        (lambda (a b) (string> (or (car a) "") (or (car b) "")))))

(defun +sleep--within (copy pos)
  "Non-nil when POS (a marker) is in the entry text of COPY (a marker)."
  (and (eq (marker-buffer copy) (marker-buffer pos))
       (<= copy pos)
       (< pos (+sleep--entry-end copy))))

(defun +sleep--save (buffers)
  "Save BUFFERS that are modified, even ones that were before.
A clock written but left unsaved never reaches vault-api's commit,
Syncthing or the Mac; `+endgame--saving' skips buffers that already had
unsaved changes (an earlier failed call)."
  (dolist (b (delete-dups (delq nil buffers)))
    (when (and (buffer-live-p b) (buffer-modified-p b))
      (with-current-buffer b (save-buffer)))))

(defun +sleep-clock-in-json (&optional now)
  "Clock in tonight's sleep, for the server. JSON
{\"state\": \"in\"|\"already\", \"night\", \"id\", \"closed\": [{\"file\",
\"heading\"}], \"files\"}. The night is NOW's (default the current time),
05:00 rule. Its day is made when missing (asking nothing), and its copy
too, even on a skipped night: clocking in means sleeping. Every open
clock in the vault is closed at NOW first. `already' (nothing written,
that night and copy returned) while any Sleep copy's clock is open, so a
second press after 05:00 doesn't split the night."
  (let* ((inhibit-interaction t)
         (+endgame--saved nil)
         (now (+sleep--now now))
         (night (+sleep-night-of-time now))
         (running (car (+sleep--open-sleep-clocks)))
         state copy closed)
    (if running
        (setq state "already" night (nth 0 running) copy (nth 3 running))
      (+endgame--saving
        (+endgame--ensure-day night)
        (setq copy (or (+sleep-copy night) (+sleep-plan night)))
        (let ((open (+sleep--open-clocks (list (expand-file-name +endgame-vault-dir))))
              touched)
          (pcase-dolist (`(,line ,start ,heading) open)
            (+sleep--close-clock line start now)
            (push (marker-buffer line) touched)
            (push `((file . ,(+endgame--relative (buffer-file-name (marker-buffer line))))
                    (heading . ,(if heading (org-with-point-at heading (+endgame--title)) "")))
                  closed))
          (+sleep--insert-clock copy (+sleep--clock-line now))
          (+sleep--save (cons (marker-buffer copy) touched))
          (setq state "in")))
      (+sleep--drop-stale-clock))
    (+endgame--json `((state . ,state)
                      (night . ,night)
                      (id . ,(org-entry-get copy "ID"))
                      (closed . ,(vconcat (nreverse closed)))
                      (files . ,(+sleep--files))))))

(defun +sleep-clock-out-json (&optional now)
  "Clock out of sleep, for the server. JSON {\"state\": \"out\"|\"none\",
\"night\", \"id\", \"minutes\", \"files\"}: the open clock on the most
recent Sleep copy that has one is closed at NOW (default the current
time). `none' (night, id and minutes null, nothing written) when no
Sleep copy has an open clock."
  (let* ((inhibit-interaction t)
         (+endgame--saved nil)
         (now (+sleep--now now))
         result)
    (+endgame--saving
      (pcase (car (+sleep--open-sleep-clocks))
        (`(,night ,line ,start ,copy)
         (let ((minutes (+sleep--close-clock line start now)))
           (+sleep--save (list (marker-buffer line)))
           (setq result `((state . "out") (night . ,night) (id . ,(org-entry-get copy "ID"))
                          (minutes . ,minutes)))))
        (_ (setq result '((state . "none") (night) (id) (minutes)))))
      (+sleep--drop-stale-clock))
    (+endgame--json (append result `((files . ,(+sleep--files)))))))

(defun +sleep--span (date start end &optional minutes)
  "(BED . WAKE) times of a night from START on DATE to END (\"HH:MM\").
MINUTES, when known, is the length; else END is on DATE, or the day
after when it isn't after START."
  (let ((bed (+sleep--time date start)))
    (cons bed
          (if minutes
              (time-add bed (* 60 minutes))
            (+sleep--time (if (> (+sleep--minutes end) (+sleep--minutes start))
                              date
                            (+sleep--add-days date 1))
                          end)))))

(defun +sleep--planned (night)
  "(BED . WAKE) of NIGHT as planned, or nil: no sleep planned.
Its copy's active stamp (none: the night was cancelled, nil), else the
default's occurrence unless it is skipped."
  (let ((copy (+sleep-copy night))
        (default (+sleep--source-range)))
    (if copy
        (pcase (+endgame-entry-time-range copy)
          ('nil nil)                    ; cancelled: its stamp went inactive
          (`(,date ,start ,end ,minutes)
           (let ((minutes (and minutes (> minutes 0) minutes)))
             (if start
                 (+sleep--span date start (or end (nth 1 default))
                               (or minutes
                                   (and (not end)
                                        (nth 3 (+endgame-entry-time-range (+sleep--source))))))
               ;; a date without a time: the default's times
               (+sleep--span (+sleep-occurrence-date night) (car default) (nth 1 default))))))
      (unless (+sleep-skipped-p night)
        (+sleep--span (+sleep-occurrence-date night) (car default) (nth 1 default))))))

(defun +sleep-next-json (&optional now)
  "The night Home Assistant should follow at NOW (default the current time). JSON
{\"night\", \"bed\", \"wake\", \"clockedIn\"}: bed and wake are local
\"YYYY-MM-DD HH:MM\", or null when that night has no sleep planned (no
alarm). Last night (the night before NOW's) while its wake is still
ahead, else NOW's night. clockedIn: some Sleep copy has an open clock."
  (let* ((inhibit-interaction t)
         (now (+sleep--now now))
         (tonight (+sleep-night-of-time now))
         (last (+sleep--add-days tonight -1))
         (last-plan (+sleep--planned last))
         (night (if (and last-plan (time-less-p now (cdr last-plan))) last tonight))
         (plan (if (equal night last) last-plan (+sleep--planned tonight)))
         (fmt (lambda (time) (and time (format-time-string "%Y-%m-%d %H:%M" time)))))
    (+endgame--json `((night . ,night)
                      (bed . ,(funcall fmt (car plan)))
                      (wake . ,(funcall fmt (cdr plan)))
                      (clockedIn . ,(if (+sleep--open-sleep-clocks) t :json-false))))))

;;; Emacs: SPC j z / SPC j Z through vault-api

;; Every sleep CLOCK line is written by the server (one writer, whoever
;; asks: the phone, HA, Emacs). Emacs calls the routes, then re-reads the
;; files they changed; when the server closed the clock Emacs had running
;; (`/sleep/in' closes every open clock), Emacs forgets it instead of
;; closing it a second time.

(defvar +sleep-api-url "https://server.tail1e29bb.ts.net:8443"
  "vault-api's address. The token is the auth-source password for host vault-api.")

(defvar org-clock-mode-line-timer)
(defvar org-clock-idle-timer)
(defvar org-mode-line-string)
(declare-function org-clock-restore-frame-title-format "org-clock")

(defun +sleep--forget-clock ()
  "Drop Emacs's running clock from memory, writing nothing.
The markers go nowhere, the start time is nil, the mode line is cleared."
  (when (timerp org-clock-mode-line-timer)
    (cancel-timer org-clock-mode-line-timer)
    (setq org-clock-mode-line-timer nil))
  (when (timerp org-clock-idle-timer)
    (cancel-timer org-clock-idle-timer)
    (setq org-clock-idle-timer nil))
  (move-marker org-clock-marker nil)
  (move-marker org-clock-hd-marker nil)
  (setq org-clock-start-time nil
        org-clock-current-task nil
        org-mode-line-string ""
        global-mode-string (delq 'org-mode-line-string global-mode-string))
  (setq org-clock-heading "")
  (when (fboundp 'org-clock-restore-frame-title-format)
    (org-clock-restore-frame-title-format))
  ;; what `org-clock-out-hook' would refresh, minus its writers (the
  ;; empty-drawer cleanup): the today panel
  (dolist (f '(+endgame-today--forget-slow +endgame-today--changed-h))
    (when (fboundp f) (funcall f)))
  (force-mode-line-update t))

(defun +sleep--clock-stale-p ()
  "Non-nil when Emacs clocks something whose CLOCK line isn't open any more.
A revert can move `org-clock-marker' off its line when the file changed
around it, so the line is looked for: an open CLOCK in the clocked buffer
started at `org-clock-start-time'. Found: the markers are put back on it
\(like `my/org-clock-heal-marker'), not stale. None: stale."
  (when (org-clocking-p)
    (with-current-buffer (marker-buffer org-clock-marker)
      (org-with-wide-buffer
       (let ((minute (lambda (time) (floor (float-time time) 60)))
             found)
         (when org-clock-start-time
           (goto-char (point-min))
           (while (and (not found) (re-search-forward +sleep--open-clock-re nil t))
             (when (= (funcall minute (org-time-string-to-time (match-string 2)))
                      (funcall minute org-clock-start-time))
               (setq found (point)))))
         (if (not found)
             t
           (move-marker org-clock-marker found)
           (save-excursion
             (goto-char found)
             (when (ignore-errors (org-back-to-heading t) t)
               (move-marker org-clock-hd-marker (point))))
           nil))))))

(defun +sleep--drop-stale-clock ()
  "Forget Emacs's running clock when its CLOCK line was closed under it."
  (when (+sleep--clock-stale-p)
    (+sleep--forget-clock)
    (message "The clock was closed elsewhere (vault-api); Emacs dropped it")))

(defun +sleep--after-revert-h ()
  "On `after-revert-hook': a reverted file with Emacs's clock in it may have closed it."
  (when (and (org-clocking-p) (eq (current-buffer) (marker-buffer org-clock-marker)))
    (+sleep--drop-stale-clock)))

(add-hook 'after-revert-hook #'+sleep--after-revert-h)

(defun +sleep--resync ()
  "Re-read the vault buffers whose files changed on disk, then drop a stale clock.
Buffers with unsaved changes are left alone."
  (dolist (buf (buffer-list))
    (let ((f (buffer-file-name buf)))
      (when (and f (file-exists-p f)
                 (file-in-directory-p f +endgame-vault-dir)
                 (not (buffer-modified-p buf))
                 (not (verify-visited-file-modtime buf)))
        (with-current-buffer buf (revert-buffer t t t)))))
  (+sleep--drop-stale-clock))

(defun +sleep--api (path)
  "POST to vault-api's PATH; the parsed JSON reply (an alist)."
  (require 'url)
  (require 'auth-source)
  (let* ((token (or (auth-source-pick-first-password :host "vault-api")
                    (user-error "No vault-api token: add \"machine vault-api password …\" to auth-source")))
         (url-request-method "POST")
         (url-request-extra-headers
          `(("Content-Type" . "application/json")
            ("Authorization" . ,(concat "Bearer " token))))
         (url-request-data "{}")
         (buf (condition-case err
                  (url-retrieve-synchronously (concat +sleep-api-url path) t t 30)
                (file-error (user-error "vault-api unreachable at %s: %s"
                                        +sleep-api-url (error-message-string err))))))
    (unless buf (user-error "vault-api didn't answer at %s" +sleep-api-url))
    (unwind-protect
        (with-current-buffer buf
          (goto-char (point-min))
          (let ((status (and (looking-at "HTTP/[0-9.]+ \\([0-9]+\\)")
                             (string-to-number (match-string 1)))))
            (re-search-forward "\r?\n\r?\n" nil 'move)
            (let ((body (decode-coding-string (buffer-substring-no-properties (point) (point-max)) 'utf-8)))
              (unless (and status (< status 300))
                (user-error "vault-api %s %s: %s" (or status "?") path (string-trim body)))
              (json-parse-string body :object-type 'alist :array-type 'list
                                 :null-object nil :false-object nil))))
      (kill-buffer buf))))

(defun +sleep--save-vault-buffers ()
  "Save what the server is about to write: unsaved journal, upcoming and
sleep source buffers, and any vault buffer with an open CLOCK line.
Other half-edited notes are left alone."
  (let ((src (ignore-errors (buffer-file-name (marker-buffer (+sleep--source)))))
        saved)
    (dolist (buf (buffer-list))
      (let ((f (buffer-file-name buf)))
        (when (and f (buffer-modified-p buf)
                   (file-in-directory-p f +endgame-vault-dir)
                   (or (file-in-directory-p f (expand-file-name org-journal-dir))
                       (file-equal-p f +endgame-upcoming-file)
                       (and src (file-equal-p f src))
                       (with-current-buffer buf
                         (org-with-wide-buffer
                          (goto-char (point-min))
                          (re-search-forward +sleep--open-clock-re nil t)))))
          (with-current-buffer buf (save-buffer))
          (push (file-name-nondirectory f) saved))))
    (when saved (message "Saved %s" (string-join saved ", ")))))

(defun +sleep--resync-later ()
  "Re-sync again once Syncthing had time to bring the server's writes over."
  (dolist (secs '(5 20))
    (run-with-timer secs nil #'+sleep--resync)))

(defun +sleep/clock-in ()
  "Clock in sleep through vault-api (POST /sleep/in): tonight's Sleep heading.
Every other open clock is closed by the server first; Emacs then re-reads
the files and drops its own clock if it was one of them."
  (interactive)
  (+sleep--save-vault-buffers)
  (let ((r (+sleep--api "/sleep/in")))
    (+sleep--resync)
    (+sleep--resync-later)
    (message "%s"
             (pcase (alist-get 'state r)
               ("already" (format "Sleep: already clocked in (night %s)" (alist-get 'night r)))
               (_ (concat (format "Sleep: clocked in (night %s)" (alist-get 'night r))
                          (when-let ((closed (alist-get 'closed r)))
                            (concat ", closed "
                                    (mapconcat (lambda (c)
                                                 (let ((h (alist-get 'heading c)))
                                                   (if (string-empty-p (or h "")) (alist-get 'file c) h)))
                                               closed ", ")))))))))

(defun +sleep/clock-out ()
  "Clock out of sleep through vault-api (POST /sleep/out)."
  (interactive)
  (+sleep--save-vault-buffers)
  (let ((r (+sleep--api "/sleep/out")))
    (+sleep--resync)
    (+sleep--resync-later)
    (message "%s"
             (pcase (alist-get 'state r)
               ("none" "Sleep: no sleep clock is open")
               (_ (format "Sleep: clocked out, %s (night %s)"
                          (org-duration-from-minutes (or (alist-get 'minutes r) 0))
                          (alist-get 'night r)))))))

(provide '+sleep)
;;; +sleep.el ends here
