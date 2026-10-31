;;; endgame-capture-test.el --- tests for +endgame-capture.el -*- lexical-binding: t; -*-
;;
;; Runs without Doom, in a throwaway vault. The habits, routines and journal
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
  "The literate config the habits, routines and journal blocks come from.")

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
                       (or (member name '("habits" "habits-linked" "routines"))
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

(defmacro +endgame-test--with-vault (&rest body)
  "Run BODY in a fresh vault: areas, upcoming, life, inbox, habits, routines, journal."
  (declare (indent 0))
  `(let* ((+endgame-test-dir (file-name-as-directory (make-temp-file "endgame-test" t)))
          (+endgame-vault-dir +endgame-test-dir)
          (org-todo-keywords '((sequence "TODO(t)" "STRT(s!)" "|" "DONE(d!)" "KILL(k@)")
                               (sequence "APPT(a)" "|" "DONE(d!)")))
          (org-log-into-drawer t)
          (org-tags-column 0)
          (org-journal-dir (expand-file-name "roam/daily/" +endgame-test-dir))
          (org-journal-file-type 'weekly)
          (org-journal-file-format "week%V-%Y-%m-%d.org")
          (org-journal-date-prefix "* ")
          (org-journal-time-prefix "** ")
          (org-journal-date-format "%A, %Y-%m-%d")
          (org-journal-file-header #'+org-journal-file-header)
          (org-journal-carryover-items "TODO=\"TODO\"-HABIT_ID={.}-ROUTINE={.}")
          (org-journal-enable-agenda-integration nil)
          (org-journal-enable-cache nil)
          (org-journal-hide-entries-p nil)
          (org-agenda-files (list (expand-file-name "roam/inbox.org" +endgame-test-dir)))
          (org-capture-templates nil)
          (+endgame--areas-cache nil)
          (+endgame-areas-file
           (+endgame-test--file
            "roam/areas.org"
            (concat "#+title: areas\n\n"
                    "* Pursuits category\n"
                    "** Learning\n:PROPERTIES:\n:AREA_TAG:      learning\n:STRATEGY:      filler\n"
                    ":BASELINE_WEEK: 4:00\n:SOURCES:       file:roam/curriculum.org\n:END:\n"
                    "** Piano\n:PROPERTIES:\n:AREA_TAG:      piano\n:STRATEGY:      filler\n"
                    ":BASELINE_DAY:  0:25\n:SOURCES:\n:END:\n"
                    "*** TODO not an area\n")))
          (+endgame-upcoming-file (+endgame-test--file "roam/upcoming.org" "#+title: upcoming\n\nstaging.\n"))
          (+endgame-life-file (+endgame-test--file "roam/life.org" "#+title: life\n\n* Appointments\n* Errands\n"))
          (+endgame-inbox-file (+endgame-test--file "roam/inbox.org" "#+title: inbox\n\nraw capture.\n"))
          (+habits-file
           (+endgame-test--file
            "roam/habits.org"
            (concat "#+title: my habits\n\n"
                    "* TODO piano\nSCHEDULED: <" (+endgame-test--date -1) " .+1d>\n"
                    ":PROPERTIES:\n:ID:       src-piano\n:STYLE:    habit\n:END:\n")))
          (+routines-file
           (+endgame-test--file
            "roam/routines.org"
            (concat "#+title: routines\n\n"
                    "* Morning routine\nwake up.\n- [ ] water\n- [ ] stretch\n"
                    "* Session routine\n- [ ] Start\n  - [ ] Clock in\n- [ ] During\n- [ ] End\n"))))
     (make-directory org-journal-dir t)
     (+endgame-test--file
      "roam/curriculum.org"
      (concat "#+title: curriculum\n\n* CS\n:LOGBOOK:\n"
              "CLOCK: [" +endgame-test-future " Wed 10:00]--[" +endgame-test-future " Wed 11:30] =>  1:30\n"
              ":END:\n"))
     (unwind-protect
         (progn ,@body)
       (dolist (b (buffer-list))
         (when (and (buffer-file-name b)
                    (string-prefix-p +endgame-test-dir (buffer-file-name b)))
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
            "* APPT barber <2031-01-06 Mon 14:00-14:45>\n")
    (goto-char (point-min))
    (should (equal (+endgame-entry-stamp) "<2031-01-03 Fri 09:00-10:00>"))
    (re-search-forward "^\\* APPT")
    (should (equal (+endgame-entry-time-range) '("2031-01-06" "14:00" "14:45" 45)))))

;;; APPT and capture

(ert-deftest +endgame-appt-is-its-own-sequence ()
  (should (member '(sequence "APPT(a)" "|" "DONE(d!)") (default-value 'org-todo-keywords))))

(ert-deftest +endgame-capture-templates ()
  (+endgame-test--with-vault
    (+endgame-capture-setup)
    (should (equal (mapcar #'car org-capture-templates) '("i" "t" "a" "e")))
    (+endgame-test--answering '("copy room keys")
      (org-capture nil "i"))
    (+endgame-test--answering '("call the bank")
      (org-capture nil "t"))
    (+endgame-test--answering '("barber" "2031-01-06 2pm+0:45")
      (org-capture nil "a"))
    (+endgame-test--answering '("50% off %t socks" "2031-01-10")
      (org-capture nil "e"))
    (let ((inbox (+endgame-test--read +endgame-inbox-file))
          (life (+endgame-test--read +endgame-life-file)))
      (should (string-match-p "^\\* TODO copy room keys\n:PROPERTIES:\n:CREATED: +\\[[-0-9]+ [^]]+\\]\n:END:" inbox))
      (should (string-match-p (concat "^\\* TODO call the bank\nSCHEDULED: <" (+endgame--today)) inbox))
      (should (string-match-p "^\\*\\* APPT barber <2031-01-06 Mon 14:00-14:45>\n:PROPERTIES:\n:CALDAV_UID: [-0-9a-f]+\n:END:" life))
      (should (string-match-p "^\\*\\* TODO 50% off %t socks\nSCHEDULED: <2031-01-10 Fri>" life))
      ;; the appointment under Appointments, the errand under Errands
      (should (< (string-match "APPT barber" life) (string-match "^\\* Errands" life)
                 (string-match "socks" life))))))

;;; Areas

(ert-deftest +endgame-areas-registry ()
  (+endgame-test--with-vault
    (let ((areas (+endgame-areas)))
      (should (equal (mapcar (lambda (a) (alist-get 'tag a)) areas) '("learning" "piano")))
      (should (equal (alist-get 'category (car areas)) "Pursuits"))
      (should (equal (alist-get 'baselineWeek (car areas)) 240))
      (should (equal (alist-get 'baselineDay (cadr areas)) 25))
      (should (equal (+endgame-area-sources "learning")
                     (list (list (expand-file-name "roam/curriculum.org" +endgame-test-dir)))))
      (should-not (+endgame-area-sources "piano"))
      (should (string-match-p "\"tag\":\"learning\"" (+endgame-areas-json))))))

;;; Sessions, routines, days

(ert-deftest +endgame-session-into-upcoming-then-day ()
  (+endgame-test--with-vault
    ;; a future day without a note: staged in upcoming
    (should (eq (+endgame-session-add "learning" (concat +endgame-test-future " 10:00-12:00")) 'upcoming))
    (let ((up (+endgame-test--read +endgame-upcoming-file)))
      (should (string-match-p
               (concat "^\\* TODO learning session \\[0/3\\] :learning:\n:PROPERTIES:\n"
                       ":ROUTINE:  Session routine\n:AREA:     learning\n:CALDAV_UID: [-0-9a-f]+\n:END:\n"
                       "<" +endgame-test-future " Wed 10:00-12:00>\n- \\[ \\] Start")
               up)))
    ;; a staged item from the calendar keeps its UID through the move
    (with-current-buffer (find-file-noselect +endgame-upcoming-file)
      (goto-char (point-max))
      (insert "* APPT not staged, other day <2031-01-09 Thu>\n"
              "* TODO piano session <" +endgame-test-future " Wed 18:00-18:30> :piano:\n"
              ":PROPERTIES:\n:ROUTINE:  Session routine\n:CALDAV_UID: uid-1@vault\n:END:\n- [ ] Start\n")
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
        (should (string-match-p "^\\*\\* DO list \\[0/3\\]" week))
        (should (string-match-p "^\\*\\*\\* TODO piano\nSCHEDULED: <2031-01-08 Wed>" week)) ; the habit
        (should (string-match-p "^\\*\\*\\* TODO learning session \\[0/3\\] :learning:" week))
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
      (should (eq (+endgame-routine-add "Morning routine" today "9:00") 'upcoming))
      (should-not (+endgame--day-marker today))
      (should (string-match-p "learning session" (+endgame-test--read +endgame-upcoming-file))))))

(ert-deftest +endgame-routine-copy-gets-its-days-stamp ()
  (+endgame-test--with-vault
    (should (eq (+endgame-routine-add "Morning routine" +endgame-test-future "7am+0:15") 'upcoming))
    (should (string-match-p (concat "^\\* TODO Morning routine \\[0/2\\]\n:PROPERTIES:\n:ROUTINE:  Morning routine\n:CALDAV_UID: [-0-9a-f]+\n:END:\n"
                                    "<" +endgame-test-future " Wed 07:00-07:15>\n- \\[ \\] water")
                            (+endgame-test--read +endgame-upcoming-file)))
    (+endgame-day-ensure +endgame-test-future)
    (should (eq (+endgame-routine-add "Session routine" +endgame-test-future nil) 'day))
    (let ((week (+endgame-test--read (buffer-file-name (marker-buffer (+endgame--day-marker +endgame-test-future))))))
      (should (string-match-p (concat "^\\*\\*\\* TODO Morning routine \\[0/2\\]\n:PROPERTIES:\n:ROUTINE:  Morning routine\n:CALDAV_UID: [-0-9a-f]+\n:END:\n<"
                                      +endgame-test-future " Wed 07:00-07:15>")
                              week))
      (should (string-match-p (concat ":ROUTINE:  Session routine\n:END:\n<" +endgame-test-future " Wed>\n")
                              week)))))

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
      (should (string-match-p "^\\*\\*\\* TODO learning session" (buffer-string))))))

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

;;; endgame-capture-test.el ends here
