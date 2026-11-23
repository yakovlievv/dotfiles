;;; endgame-capture-test.el --- tests for +endgame-capture.el -*- lexical-binding: t; -*-
;;
;; Runs without Doom, in a throwaway vault. The habits and journal
;; code the module builds on is read straight out of the literate config, so
;; the tests run against the real thing:
;;
;; emacs -Q --batch -L ~/.config/emacs/.local/straight/build-31.1/org \
;;   -L ~/.config/emacs/.local/straight/build-31.1/org-journal \
;;   -l ~/.config/doom/tests/endgame-capture-test.el -f ert-run-tests-batch-and-exit

(require 'ert)
(require 'cl-lib)
(require 'org)
(require 'org-id)
(require 'org-capture)

(defvar +endgame-test-config (expand-file-name "~/org/roam/config/doom-config.org")
  "The literate config the habits and journal blocks come from.")

;; Doom macros used in those blocks.
(defmacro after! (feature &rest body)
  `(with-eval-after-load ',feature ,@body))
(defmacro map! (&rest _) nil)

(defun +endgame-test--config-blocks ()
  "The emacs-lisp blocks of the config that the module builds on."
  (with-temp-buffer
    (insert-file-contents +endgame-test-config)
    (let (blocks)
      (goto-char (point-min))
      (while (re-search-forward "^\\(#\\+name: \\(.*\\)\n\\)?#\\+begin_src emacs-lisp.*\n" nil t)
        (let ((name (match-string 2))
              (beg (point)))
          (re-search-forward "^#\\+end_src")
          (let ((code (buffer-substring beg (match-beginning 0))))
            (when (and (not (string-match-p "<<" code)) ; the tangled test files
                       (or (member name '("repeat-skip" "habits"))
                      (string-match-p "(defun \\+org-journal-init-day" code)
                          (string-match-p "org-use-property-inheritance" code)))
              (push code blocks)))))
      (nreverse blocks))))

(setq org-id-locations-file (make-temp-file "endgame-test-ids")
      org-id-track-globally nil
      custom-file (make-temp-file "endgame-test-custom"))
(dolist (code (+endgame-test--config-blocks))
  (eval (car (read-from-string (concat "(progn " code "\n)"))) t))
(require 'org-journal)
(load (expand-file-name "../+endgame-capture.el" (file-name-directory (or load-file-name buffer-file-name))) nil t)
(load (expand-file-name "../+sleep.el" (file-name-directory (or load-file-name buffer-file-name))) nil t)

(defvar +endgame-test-dir nil)

(defun +endgame-test--file (name text)
  (let ((f (expand-file-name name +endgame-test-dir)))
    (make-directory (file-name-directory f) t)
    (with-temp-file f (insert text))
    f))

(defun +endgame-test--read (file)
  (with-current-buffer (find-file-noselect file)
    (buffer-substring-no-properties (point-min) (point-max))))

(defun +endgame-test--date (&optional offset)
  (format-time-string "%Y-%m-%d" (time-add (+endgame--date-time) (days-to-time (or offset 0)))))

(defconst +endgame-test-future "2031-01-08"
  "A Wednesday far enough ahead to stay in the future.")

(defconst +endgame-test-sleep-source
  (concat "#+title: sleep optimization system\n\n"
          "* Components\n"
          "** Sleep schedule\n:PROPERTIES:\n:ID:       src-sleep\n:END:\n"
          "<2031-01-01 Wed 01:00-09:00 +1d>\nThe default night.\n"
          "** Tools\n")
  "The sleep system note, with the default night (`+sleep-source-id').")

(defmacro +endgame-test--with-vault (&rest body)
  "Run BODY in a fresh vault: areas, upcoming, tasks, habits, session templates,
journal, the sleep system note. The day ends at 05:00, as in the config."
  (declare (indent 0))
  `(let* ((+endgame-test-dir (file-name-as-directory (make-temp-file "endgame-test" t)))
          (+endgame-vault-dir +endgame-test-dir)
          (org-todo-keywords '((sequence "TODO(t)" "STRT(s!)" "|" "DONE(d!)" "KILL(k@)")
                               (sequence "NOPLAN(N)" "PLANNED(L)" "|" "NOTPAID($!)")))
          (org-log-into-drawer t)
          (org-tags-column 0)
          (org-journal-dir (expand-file-name "roam/daily/" +endgame-test-dir))
          (org-journal-file-type 'weekly)
          (org-journal-file-format "week%V-%Y-%m-%d.org")
          (org-journal-date-prefix "* ")
          (org-journal-time-prefix "** ")
          (org-journal-date-format "%A, %Y-%m-%d")
          (org-journal-file-header #'+org-journal-file-header)
          (org-journal-carryover-items "TODO=\"TODO\"")
          (org-journal-enable-agenda-integration nil)
          (org-journal-enable-cache nil)
          (org-journal-hide-entries-p nil)
          (org-agenda-files (list (expand-file-name "roam/tasks.org" +endgame-test-dir)))
          (org-capture-templates nil)
          (org-extend-today-until 5)
          (+sleep-source-id "src-sleep")
          (+endgame--areas-cache nil)
          (+endgame-areas-file
           (+endgame-test--file
            "roam/areas.org"
            (concat "#+title: areas\n\n"
                    "* Pursuits category\n"
                    "** Learning\n:PROPERTIES:\n:AREA_TAG:      learning\n:STRATEGY:      filler\n"
                    ":BASELINE_WEEK: 4:00\n:SOURCES:       file:roam/curriculum.org\n:SESSION_TEMPLATE: deep session\n:END:\n"
                    "** Piano\n:PROPERTIES:\n:AREA_TAG:      piano\n:STRATEGY:      filler\n"
                    ":BASELINE_DAY:  0:25\n:SOURCES:\n:END:\n"
                    "* Life category\n"
                    "** Social\n:PROPERTIES:\n:AREA_TAG:      social\n:FALLBACK:      yes\n:SOURCES:\n:END:\n"
                    "** Tutoring\n:PROPERTIES:\n:AREA_TAG:      tutoring\n:SESSION_STATES: NOPLAN PLANNED\n:SOURCES:\n:END:\n"
                    "*** TODO not an area\n")))
          (+endgame-upcoming-file (+endgame-test--file "roam/upcoming.org" "#+title: upcoming\n\nstaging.\n"))
          (+endgame-tasks-file (+endgame-test--file "roam/tasks.org" "#+title: tasks\n\n* Inbox\nraw capture.\n* tasks\n"))
          (+habits-file
           (+endgame-test--file
            "roam/habits.org"
            (concat "#+title: my habits\n\n"
                    "* TODO piano\nSCHEDULED: <" (+endgame-test--date -1) " .+1d>\n"
                    ":PROPERTIES:\n:ID:       src-piano\n:STYLE:    habit\n:END:\n")))
          (+endgame-templates-file
           (+endgame-test--file
            "roam/templates.org"
            (concat "#+title: session templates\n\n"
                    "* deep session\nhow to run one.\n- [X] Start\n  - [ ] Clock in\n- [ ] During\n- [ ] End\n"
                    "* piano session\n- [ ] scales\n"))))
     (make-directory org-journal-dir t)
     (+endgame-test--file "roam/sleep_system.org" +endgame-test-sleep-source)
     (+endgame-test--file
      "roam/curriculum.org"
      (concat "#+title: curriculum\n\n* CS\n:LOGBOOK:\n"
              "CLOCK: [" +endgame-test-future " Wed 10:00]--[" +endgame-test-future " Wed 11:30] =>  1:30\n"
              ":END:\n"))
     (unwind-protect
         (progn ,@body)
       (dolist (b (buffer-list))
         (when (and (buffer-file-name b)
                    ;; truenames: on macOS the temp dir is /var, a symlink to /private/var
                    (string-prefix-p (file-truename +endgame-test-dir) (file-truename (buffer-file-name b))))
           (with-current-buffer b (set-buffer-modified-p nil))
           (kill-buffer b)))
       (delete-directory +endgame-test-dir t))))

(defmacro +endgame-test--answering (answers &rest body)
  "Run BODY with the minibuffer prompts answered from ANSWERS, in order."
  (declare (indent 1))
  `(let ((answers ,answers)
         (org-read-date-popup-calendar nil))
     (cl-letf (((symbol-function 'read-string) (lambda (&rest _) (pop answers)))
               ((symbol-function 'read-from-minibuffer) (lambda (&rest _) (pop answers)))
               ((symbol-function 'completing-read) (lambda (&rest _) (pop answers)))
               ((symbol-function 'y-or-n-p) #'ignore))
       ,@body)))

;;; Timestamps

(ert-deftest +endgame-stamps-read-like-orgs-date-prompt ()
  (let ((sun (encode-time 0 0 12 5 1 2031)))
    ;; weekdays count from today, like org's prompt: the next Monday
    (should (string-match-p "\\`<[-0-9]+ Mon 14:00-14:45>\\'" (+endgame--stamp "mon 2pm+0:45")))
    (should (string> (substring (+endgame--stamp "mon 14:00-14:45") 1 11) (+endgame--today)))
    (should (equal (+endgame--stamp "2031-01-06 2pm+0:45") "<2031-01-06 Mon 14:00-14:45>"))
    ;; a bare time is on the given day
    (should (equal (+endgame--stamp "9:00" sun t) "<2031-01-05 Sun 09:00>"))
    (should (equal (+endgame--stamp "2031-01-07" sun) "<2031-01-07 Tue>")))
  (should (equal (+endgame--stamp-range "<2031-01-06 Mon 14:00-14:45>") '("2031-01-06" "14:00" "14:45" 45)))
  (should (equal (+endgame--stamp-range "<2031-01-06 Mon 23:00>--<2031-01-07 Tue 01:00>")
                 '("2031-01-06" "23:00" "01:00" 120)))
  (should (equal (+endgame--stamp-range "<2031-01-06 Mon>") '("2031-01-06" nil nil nil))))

(ert-deftest +endgame-entry-stamp-skips-planning-and-properties ()
  (with-temp-buffer
    (org-mode)
    (insert "* TODO a\nSCHEDULED: <2031-01-01 Wed>\n:PROPERTIES:\n:GCAL: <2031-01-02 Thu>\n:END:\n"
            "<2031-01-03 Fri 09:00-10:00>\n** child <2031-01-04 Sat>\n"
            "* barber <2031-01-06 Mon 14:00-14:45>\n")
    (goto-char (point-min))
    (should (equal (+endgame-entry-stamp) "<2031-01-03 Fri 09:00-10:00>"))
    (re-search-forward "^\\* barber")
    (should (equal (+endgame-entry-time-range) '("2031-01-06" "14:00" "14:45" 45)))))

;;; Events and capture

(ert-deftest +endgame-appt-keyword-is-gone ()
  "An event is a plain heading: nothing defines the APPT keyword any more."
  (should-not (member '(sequence "APPT(a)" "|" "DONE(d!)") (default-value 'org-todo-keywords))))

(ert-deftest +endgame-capture-inbox-and-task ()
  (+endgame-test--with-vault
    (let ((a (+endgame-capture "inbox" '((title . "copy room keys")))))
      (should (equal (alist-get 'where a) "inbox"))
      (should (alist-get 'id a)))
    (+endgame-capture "inbox" '((title . "call the bank") (date . "2031-01-10")))
    ;; a task of an area, tagged, scheduled; no area: the FALLBACK area
    (+endgame-capture "task" '((title . "50% off %t socks") (area . "piano") (date . "2031-01-10")))
    (let ((a (+endgame-capture "task" '((title . "fix the door") (tags . ("ai_gen"))))))
      (should (equal (alist-get 'where a) "tasks")))
    (let ((tasks (+endgame-test--read +endgame-tasks-file)))
      (should (string-match-p "^\\*\\* TODO copy room keys\n:PROPERTIES:\n:ID: [-0-9a-f]+\n:CREATED: \\[[-0-9]+ [^]]+\\]\n:END:" tasks))
      (should (string-match-p "^\\*\\* TODO call the bank\nSCHEDULED: <2031-01-10 Fri>" tasks))
      (should (string-match-p "^\\*\\* TODO 50% off %t socks :piano:\nSCHEDULED: <2031-01-10 Fri>" tasks))
      (should (string-match-p "^\\*\\* TODO fix the door :social:ai_gen:\n" tasks))
      ;; the inbox first, then the tasks heading
      (should (< (string-match "^\\* Inbox" tasks) (string-match "copy room keys" tasks)
                 (string-match "call the bank" tasks) (string-match "^\\* tasks" tasks)
                 (string-match "socks" tasks) (string-match "fix the door" tasks))))))

(ert-deftest +endgame-capture-refuses-what-it-cant-make ()
  (+endgame-test--with-vault
    (should-error (+endgame-capture "task" '((title . "x") (area . "knitting"))) :type 'error)
    (should-error (+endgame-capture "session" '((area . "piano"))))      ; a session needs a time
    (should-error (+endgame-capture "inbox" '((title . "")))) 
    (should-error (+endgame-capture "event" '((title . "x"))))
    (should-error (+endgame-capture "inbox" '((title . "x") (body . "* a heading"))))
    (should-error (+endgame-capture "task" '((title . "x") (props . ((ID . "forced"))))))
    (should (string-match-p "\\[invalid\\]" (condition-case e (+endgame-capture "task" '((title . "x") (area . "knitting")))
                                              (error (error-message-string e)))))))

(ert-deftest +endgame-capture-session-with-a-template ()
  (+endgame-test--with-vault
    ;; the area's default template is offered by the menu; the server passes the name
    (should (equal (+endgame-template-names) '("deep session" "piano session")))
    (let ((a (+endgame-capture "session" `((area . "learning") (date . ,+endgame-test-future) (time . "10:00") (end . "12:00")
                                           (template . "Deep Session")))))
      (should (equal (alist-get 'where a) "upcoming"))
      (should (alist-get 'uid a)))
    (should (string-match-p
             (concat "^\\* learning session <" +endgame-test-future " Wed 10:00-12:00> \\[0/3\\] :learning:\n:PROPERTIES:\n"
                     ":AREA: learning\n:CALDAV_UID: [-0-9a-f]+\n:END:\n"
                     "- \\[ \\] Start\n  - \\[ \\] Clock in\n- \\[ \\] During\n- \\[ \\] End\n")
             (+endgame-test--read +endgame-upcoming-file)))
    ;; no template: a plain block; the calendar's own uid and properties kept
    (+endgame-capture "session" `((area . "social") (title . "dentist") (date . ,+endgame-test-future) (time . "9:30")
                                  (props . (("CALDAV_UID" . "uid-9@vault") ("ALERT" . "15m") ("LOCATION" . "Main St")))))
    (should (string-match-p
             (concat "^\\* dentist <" +endgame-test-future " Wed 09:30> :social:\n:PROPERTIES:\n:AREA: social\n"
                     ":CALDAV_UID: uid-9@vault\n:ALERT: 15m\n:LOCATION: Main St\n:END:\n")
             (+endgame-test--read +endgame-upcoming-file)))
    (should-error (+endgame-capture "session" `((area . "piano") (time . "10:00") (template . "no such one"))))))

(ert-deftest +endgame-capture-json-saves-and-answers ()
  (+endgame-test--with-vault
    (let ((out (json-parse-string
                (+endgame-capture-json "{\"kind\":\"task\",\"title\":\"buy bread\",\"area\":\"piano\",\"props\":{\"CALDAV_UID\":\"u-1\"}}")
                :object-type 'alist)))
      (should (equal (alist-get 'where out) "tasks"))
      (should (equal (alist-get 'uid out) "u-1"))
      (should (equal (append (alist-get 'files out) nil) '("roam/tasks.org")))
      (should-not (buffer-modified-p (find-buffer-visiting +endgame-tasks-file))))
    (should-error (+endgame-capture-json "{\"kind\":\"task\",\"title\":\"x\",\"area\":\"nope\"}"))))

(ert-deftest +endgame-session-p-no-keyword-or-a-session-state ()
  (+endgame-test--with-vault
    (with-temp-buffer
      (org-mode)
      (insert "* dentist <2031-01-08 Wed 09:30>\n"
              "* TODO call <2031-01-08 Wed 09:30>\n"
              "* PLANNED Lesson 3\nSCHEDULED: <2031-01-08 Wed 17:00-18:00>\n"
              "* walk <2031-01-08 Wed>\n")
      (goto-char (point-min))
      (should (+endgame-session-p))
      (forward-line 1) (should-not (+endgame-session-p))
      (forward-line 1) (should (+endgame-session-p))
      (forward-line 2) (should-not (+endgame-session-p)))))

;;; Areas

(ert-deftest +endgame-areas-registry ()
  (+endgame-test--with-vault
    (let ((areas (+endgame-areas)))
      (should (equal (mapcar (lambda (a) (alist-get 'tag a)) areas) '("learning" "piano" "social" "tutoring")))
      (should (equal (alist-get 'template (car areas)) "deep session"))
      (should-not (alist-get 'template (cadr areas)))
      (should (eq (alist-get 'fallback (nth 2 areas)) t))
      (should (equal (alist-get 'sessionStates (nth 3 areas)) '("NOPLAN" "PLANNED")))
      (should (equal (+endgame-session-states) '("NOPLAN" "PLANNED")))
      (should (equal (alist-get 'category (car areas)) "Pursuits"))
      (should (equal (alist-get 'baselineWeek (car areas)) 240))
      (should (equal (alist-get 'baselineDay (cadr areas)) 25))
      (should (equal (+endgame-area-sources "learning")
                     (list (list (expand-file-name "roam/curriculum.org" +endgame-test-dir)))))
      (should-not (+endgame-area-sources "piano"))
      (should (string-match-p "\"tag\":\"learning\"" (+endgame-areas-json))))))

(ert-deftest +endgame-area-sources-narrowest-wins ()
  "One file, one area: a topic tag beats a node-type tag whatever the order,
a file: source beats any tag, and of two topic tags the narrower wins."
  (+endgame-test--with-vault
    (cl-flet ((note (name tags) (+endgame-test--file (concat "roam/" name ".org")
                                                     (concat "#+title: " name "\n#+filetags: " tags "\n\n* item\n")))
              (files (tag) (sort (mapcar (lambda (s) (file-name-nondirectory (car s))) (+endgame-area-sources tag)) #'string<)))
      (note "sys" ":system:") (note "proj" ":project:")
      (note "both" ":system:cs:") (note "proj-cs" ":project:cs:") (note "cs" ":cs:")
      (note "pinned" ":system:") (note "narrow" ":x:y:") (note "wide" ":x:")
      (note "tie1" ":p:q:")
      (let* ((+endgame--areas-cache nil)
             ;; maintenance is listed FIRST: order alone would give it every shared file
             (+endgame-areas-file
              (+endgame-test--file
               "roam/areas2.org"
               (concat "#+title: areas\n\n* Cat\n"
                       "** Maintenance\n:PROPERTIES:\n:AREA_TAG: maintenance\n:SOURCES: tag:system tag:project\n:END:\n"
                       "** Coding\n:PROPERTIES:\n:AREA_TAG: coding\n:SOURCES: tag:cs\n:END:\n"
                       "** Piano\n:PROPERTIES:\n:AREA_TAG: piano\n:SOURCES: file:roam/pinned.org\n:END:\n"
                       "** Wide\n:PROPERTIES:\n:AREA_TAG: wide\n:SOURCES: tag:x\n:END:\n"
                       "** Narrow\n:PROPERTIES:\n:AREA_TAG: narrow\n:SOURCES: tag:y\n:END:\n"
                       "** First\n:PROPERTIES:\n:AREA_TAG: first\n:SOURCES: tag:p\n:END:\n"
                       "** Second\n:PROPERTIES:\n:AREA_TAG: second\n:SOURCES: tag:q\n:END:\n"))))
        (should (equal (files "maintenance") '("proj.org" "sys.org")))
        (should (equal (files "coding") '("both.org" "cs.org" "proj-cs.org")))
        (should (equal (files "piano") '("pinned.org")))
        (should (equal (files "narrow") '("narrow.org")))
        (should (equal (files "wide") '("wide.org")))
        (should (equal (files "first") '("tie1.org")))
        (should-not (files "second"))))))

;;; Sessions, days

(ert-deftest +endgame-session-into-upcoming-then-day ()
  (+endgame-test--with-vault
    ;; a future day without a note: staged in upcoming
    (should (eq (+endgame-session-add "learning" (concat +endgame-test-future " 10:00-12:00")) 'upcoming))
    (let ((up (+endgame-test--read +endgame-upcoming-file)))
      (should (string-match-p
               (concat "^\\* learning session <" +endgame-test-future " Wed 10:00-12:00> :learning:\n:PROPERTIES:\n"
                       ":AREA: learning\n:CALDAV_UID: [-0-9a-f]+\n:END:\n")
               up)))
    ;; a staged item from the calendar keeps its UID through the move
    (with-current-buffer (find-file-noselect +endgame-upcoming-file)
      (goto-char (point-max))
      (insert "* not staged, other day <2031-01-09 Thu>\n"
              "* piano session <" +endgame-test-future " Wed 18:00-18:30> :piano:\n"
              ":PROPERTIES:\n:AREA: piano\n:CALDAV_UID: uid-1@vault\n:END:\n- [ ] Start\n")
      (save-buffer))
    (should (equal (+endgame-area-planned "learning" +endgame-test-future) 120))
    (should (equal (+endgame-area-planned "piano" +endgame-test-future) 30))
    (let ((out (json-parse-string (+endgame-day-ensure +endgame-test-future))))
      (should (eq (gethash "created" out) t))
      (should (= (gethash "moved" out) 2))
      (should (string-match-p "week02-2031-01-06\\.org\\'" (gethash "file" out)))
      (let ((week (+endgame-test--read (gethash "file" out))))
        (should (string-match-p "^\\* Wednesday, 2031-01-08 :daily:\n:PROPERTIES:\n:CREATED:  20310108\n:ID: " week))
        (should (string-match-p (concat "#\\+BEGIN: clocktable .*:block " +endgame-test-future) week))
        (should (string-match-p "^\\*\\* DO list \\[0/0\\]" week))
        (should (string-match-p "^\\*\\*\\* learning session <" week))
        (should (string-match-p ":CALDAV_UID: uid-1@vault" week)))
      (let ((up (+endgame-test--read +endgame-upcoming-file)))
        (should-not (string-match-p "session" up))
        (should (string-match-p "not staged, other day" up))))
    ;; again: nothing new
    (let ((out (json-parse-string (+endgame-day-ensure +endgame-test-future))))
      (should (eq (gethash "created" out) :false))
      (should (= (gethash "moved" out) 0)))
    ;; the day exists now: a new session goes straight into it
    (should (eq (+endgame-session-add "piano" (concat "<" +endgame-test-future " Wed 20:00-20:25>")) 'day))
    (should (equal (+endgame-area-planned "piano" +endgame-test-future) 55))
    (should (equal (+endgame-area-clocked "learning" +endgame-test-future) 90))
    (let ((report (+endgame-areas-report +endgame-test-future)))
      (should (equal (alist-get 'clocked (car report)) 90))
      (should (equal (alist-get 'planned (car report)) 120))
      (should-not (alist-get 'clocked (cadr report))))))

(ert-deftest +endgame-server-never-makes-a-day ()
  ;; the calendar or the phone (no ASK): today without a note stays staged
  (+endgame-test--with-vault
    (let ((today (+endgame--today)))
      (should-not (+endgame--day-marker today))
      (should (eq (+endgame-session-add "learning" (concat today " 10:00-12:00")) 'upcoming))
      (should-not (+endgame--day-marker today))
      (should (string-match-p "learning session" (+endgame-test--read +endgame-upcoming-file))))))

(ert-deftest +endgame-interactive-day-gets-staged-items ()
  (+endgame-test--with-vault
    (+endgame-session-add "learning" (concat +endgame-test-future " 10:00-12:00"))
    ;; making the day by hand: org-journal's entry hook runs `+org-journal-init-day'
    (add-hook 'org-journal-after-entry-create-hook #'+org-journal-init-day)
    (unwind-protect
        (+endgame-test--answering nil
          (save-window-excursion
            (org-journal-new-entry nil (+endgame--date-time +endgame-test-future))))
      (remove-hook 'org-journal-after-entry-create-hook #'+org-journal-init-day))
    (should-not (string-match-p "learning session" (+endgame-test--read +endgame-upcoming-file)))
    (with-current-buffer (marker-buffer (+endgame--day-marker +endgame-test-future))
      (should (string-match-p "^\\*\\*\\* learning session" (buffer-string))))))

(ert-deftest +endgame-carried-over-do-list-merges-into-the-days ()
  (+endgame-test--with-vault
    (let ((day (+endgame-test--file
                "roam/daily/week02-2031-01-06.org"
                (concat "* Wednesday, 2031-01-08\n:PROPERTIES:\n:ID:       d\n:END:\n"
                        "** DO list [0/1]\n*** TODO habit copy\n"
                        "** DO list [1/9]\n*** TODO carried\n*** TODO carried too\n** 10:00\nprose\n"))))
      (with-current-buffer (find-file-noselect day)
        (should (= 1 (+endgame--merge-do-lists (+endgame--day-marker +endgame-test-future))))
        (should (equal (buffer-string)
                       (concat "* Wednesday, 2031-01-08\n:PROPERTIES:\n:ID:       d\n:END:\n"
                               "** DO list [0/3]\n*** TODO habit copy\n*** TODO carried\n*** TODO carried too\n"
                               "** 10:00\nprose\n")))))))

(ert-deftest +endgame-areas-dynamic-block ()
  (+endgame-test--with-vault
    (+endgame-session-add "learning" (concat +endgame-test-future " 10:00-12:00"))
    (with-temp-buffer
      (org-mode)
      (insert "#+BEGIN: endgame-areas :tstart \"<" +endgame-test-future ">\" :tend \"<2031-01-09>\"\n#+END:\n")
      (goto-char (point-min))
      (org-update-dblock)
      (let ((text (buffer-string)))
        (should (string-match-p "#\\+CAPTION: Learning :learning: — planned 2:00, clocked 1:30, baseline 4:00/week" text))
        (should (string-match-p "| curriculum.org +| \\*File time\\* +| \\*1:30\\* |" text))
        (should-not (string-match-p "Piano" text))
        (should (string-match-p "\n#\\+END:" text))))))


(ert-deftest +endgame-day-ensure-writes-the-phones-answers ()
  ;; the phone asked the last-night and morning questions itself: both go
  ;; on last night's Sleep heading (night 01-07, no day note: in upcoming)
  (+endgame-test--with-vault
    (let ((json (+endgame-day-ensure +endgame-test-future
                                     '("2031-01-07 23:30" "2031-01-08 07:10")
                                     '(3 7 "6" "  ok  "))))
      (should (equal (alist-get 'created (json-parse-string json :object-type 'alist)) t))
      (let ((night (+sleep-copy "2031-01-07"))
            (day (+endgame--day-marker +endgame-test-future)))
        (should (string-match-p "CLOCK: \\[2031-01-07 Tue 23:30\\]--\\[2031-01-08 Wed 07:10\\] =>  7:40"
                                (+endgame-test--read (buffer-file-name (marker-buffer night)))))
        (should (equal (org-entry-get night "MORNING_HEADACHE") "3"))
        (should (equal (org-entry-get night "MORNING_FRESHNESS") "7"))
        (should (equal (org-entry-get night "MORNING_MOOD") "6"))
        (should-not (org-entry-get night "MORNING_NOTES"))
        (should (string-match-p "\nok\n" (+endgame-test--read (buffer-file-name (marker-buffer night)))))
        (should-not (org-entry-get day "SLEEP_TIME"))
        (should-not (org-entry-get day "MORNING_MOOD"))
        (should-not (buffer-modified-p (marker-buffer night)))
        (should-not (buffer-modified-p (marker-buffer day)))))
    ;; an existing day: only the morning
    (+endgame-day-ensure +endgame-test-future nil '(5 5 5 ""))
    (should (equal (org-entry-get (+sleep-copy "2031-01-07") "MORNING_MOOD") "5"))
    ;; bad answers are refused
    (should-error (+endgame-day-ensure +endgame-test-future nil '(0 5 5 nil)))
    (should-error (+endgame-day-ensure +endgame-test-future '("2031-01-08 9:00" "2031-01-08 7:00") nil))))

(ert-deftest +endgame-move-to-day-moves-the-date-and-the-heading ()
  (+endgame-test--with-vault
    (+endgame-day-ensure +endgame-test-future)
    (should (eq (+endgame-session-add "learning" (concat +endgame-test-future " 10:00-12:00")) 'day))
    (let* ((week (lambda () (+endgame-test--read (buffer-file-name (marker-buffer (+endgame--day-marker +endgame-test-future))))))
           (m (with-current-buffer (marker-buffer (+endgame--day-marker +endgame-test-future))
                (goto-char (point-min))
                (re-search-forward "^\\*\\*\\* learning session")
                (point-marker))))
      (should (+endgame-day-item-p m))
      ;; what the old path left: a SCHEDULED next to the timestamp
      (org-with-point-at m (org-schedule nil "2031-01-09"))
      ;; the next day has no note: into upcoming, time kept, SCHEDULED gone
      (let ((json (json-parse-string
                   (+endgame-move-to-day-json (buffer-file-name (marker-buffer m))
                                              (with-current-buffer (marker-buffer m) (line-number-at-pos m))
                                              nil "2031-01-09")
                   :object-type 'alist)))
        (should (equal (alist-get 'where json) "upcoming"))
        (should (alist-get 'id json)))
      (should-not (string-match-p "learning session" (funcall week)))
      (should (string-match-p "^\\*\\* DO list \\[[0-9]+/[0-9]+\\]" (funcall week)))
      (let ((up (+endgame-test--read +endgame-upcoming-file)))
        (should (string-match-p (concat "^\\* learning session <2031-01-09 Thu 10:00-12:00> :learning:\n:PROPERTIES:\n"
                                        "\\(?:.*\n\\)*?:END:\n")
                                up))
        (should-not (string-match-p "SCHEDULED" up)))
      ;; making that day moves it in
      (+endgame-day-ensure "2031-01-09")
      (should (string-match-p "learning session" (+endgame-test--read (buffer-file-name (marker-buffer (+endgame--day-marker "2031-01-09"))))))
      (should-not (string-match-p "learning session" (+endgame-test--read +endgame-upcoming-file)))
      ;; and back into an existing day, with a new time
      (let ((back (with-current-buffer (marker-buffer (+endgame--day-marker "2031-01-09"))
                    (goto-char (point-min))
                    (re-search-forward "^\\*\\*\\* learning session")
                    (point-marker))))
        (+endgame--saving (+endgame-move-to-day back +endgame-test-future "14:00" "15:30")))
      (should (string-match-p "<2031-01-08 Wed 14:00-15:30>" (funcall week))))))

(ert-deftest +endgame-move-to-day-a-plain-event ()
  (+endgame-test--with-vault
    ;; an event, a plain heading with a stamp: only its timestamp moves
    (with-current-buffer (find-file-noselect +endgame-tasks-file)
      (goto-char (point-max))
      (insert "** barber\n<2031-01-08 Wed 14:00-14:45>\n** TODO call bank\nSCHEDULED: <2031-01-08 Wed>\n")
      (save-buffer))
    (let ((json (json-parse-string (+endgame-move-to-day-json +endgame-tasks-file 6 nil "2031-01-10") :object-type 'alist)))
      (should (equal (alist-get 'where json) "same")))
    (should (string-match-p "^\\*\\* barber\n:PROPERTIES:\n:ID: .*\n:END:\n<2031-01-10 Fri 14:00-14:45>"
                            (+endgame-test--read +endgame-tasks-file)))
    ;; a plain task isn't a day item: refused, SCHEDULED is its path
    (should-error (+endgame-move-to-day-json +endgame-tasks-file 8 nil "2031-01-10"))
    ))

(ert-deftest +endgame-area-planned-counts-timed-entries-in-sources ()
  ;; lessons in a tutoring lesson plan count as planned, like sessions;
  ;; time covered twice (a session over a lesson) counts once
  (+endgame-test--with-vault
    (+endgame-session-add "learning" (concat "<" +endgame-test-future " Wed 10:00-12:00>"))
    (should (equal (+endgame-area-planned "learning" +endgame-test-future) 120))
    (with-current-buffer (find-file-noselect (expand-file-name "roam/curriculum.org" +endgame-test-dir))
      (goto-char (point-max))
      (insert "* Lesson 1 <" +endgame-test-future " Wed 11:30-12:30>\n"
              "** Pre-lesson\n*** TODO prepare\nDEADLINE: <" +endgame-test-future " Wed>\n"
              "* Lesson 2 <" +endgame-test-future " Wed 16:00-17:00>\n"
              "* KILL Lesson 3 <" +endgame-test-future " Wed 18:00-19:00>\n"
              "* DONE Lesson 5\nCLOSED: [" +endgame-test-future " Wed 20:00] SCHEDULED: <"
              +endgame-test-future " Wed 19:00-20:00>\n"
              "* TODO due then\nDEADLINE: <" +endgame-test-future " Wed 21:00-22:00>\n"
              "* untimed <" +endgame-test-future " Wed>\n"
              "* Lesson 4, other day <2031-01-09 Thu 16:00-17:00>\n")
      (save-buffer))
    (should (equal (+endgame-area-timed "learning" +endgame-test-future)
                   `((,+endgame-test-future "11:30" 60) (,+endgame-test-future "16:00" 60)
                     (,+endgame-test-future "19:00" 60))))
    ;; 10:00-12:30, 16:00-17:00 and 19:00-20:00
    (should (equal (+endgame-area-planned "learning" +endgame-test-future) 270))
    (should (equal (+endgame-area-planned "learning" +endgame-test-future "2031-01-09") 330))
    ;; an area without sources: only its sessions
    (should (equal (+endgame-area-planned "piano" +endgame-test-future) 0))))


(defun +endgame-test--count (re text)
  (let ((n 0) (start 0))
    (while (string-match re text start)
      (setq n (1+ n) start (match-end 0)))
    n))

(ert-deftest +endgame-skip-json-adds-a-date ()
  (+endgame-test--with-vault
    (let ((out (json-parse-string (+endgame-skip-json +habits-file nil "src-piano" "2031-01-09"))))
      (should (equal (gethash "skip" out) ["2031-01-09"])))
    (let ((out (json-parse-string (+endgame-skip-json +habits-file 3 nil "2031-01-08"))))
      (should (equal (gethash "skip" out) ["2031-01-08" "2031-01-09"])))
    (should (string-match-p ":SKIP: +2031-01-08 2031-01-09" (+endgame-test--read +habits-file)))))

;;; endgame-capture-test.el ends here
