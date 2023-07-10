(defpackage letty
  (:use #:cl)
  (:import-from #:alexandria)
  (:import-from #:bordeaux-threads)
  (:import-from #:log4cl)
  (:import-from #:lparallel))

(in-package letty)

;; Life cycle

(define-condition stop-error (error) ())

(defclass life-cycle ()
  ((%lock :initform (bt:make-lock))
   (%state :initform :stopped)))

(defun set-started (life-cycle)
  (with-slots (%state) life-cycle
    (when (eq %state :starting)
      (setf %state :started)
      (log:debug "STARTED ~a" life-cycle))))

(defun set-starting (life-cycle)
  (log:debug "STARTING ~a" life-cycle)
  (setf (slot-value life-cycle '%state) :starting))

(defun set-stopping (life-cycle)
  (log:debug "STOPPING ~a" life-cycle)
  (setf (slot-value life-cycle '%state) :stopping))

(defun set-stopped (life-cycle)
  (with-slots (%state) life-cycle
    (when (eq %state :stopping)
      (setf %state :stopped)
      (log:debug "STOPPED ~a" life-cycle))))

(defun set-failed (life-cycle condition)
  (setf (slot-value life-cycle '%state) :failed)
  (log:debug "FAILED ~a: ~a" life-cycle condition))

(defgeneric start (life-cycle))

(defgeneric stop (life-cycle))

;; (declaim (optimize debug))

(defmethod start :around ((life-cycle life-cycle))
  (with-slots (%lock %state) life-cycle
    (bt:with-lock-held (%lock)
      (handler-case
          (case %state
            (:started
             (values))
            ((:starting :stopping)
             (error "Illegal state: ~a" %state))
            (t
             (handler-case
                 (progn
                   (set-starting life-cycle)
                   (call-next-method life-cycle)
                   (set-started life-cycle))
               (stop-error (e)
                 (log:debug "Unable to stop ~a" e)
                 (set-stopping life-cycle)
                 (stop life-cycle)
                 (set-stopped life-cycle)))))
        (t (c)
          (set-failed life-cycle c)
          (error c))))))

(defmethod stop :around ((life-cycle life-cycle))
  (with-slots (%lock %state) life-cycle
    (bt:with-lock-held (%lock)
      (handler-case
          (case %state
            (:stopped
             (values))
            ((:starting :stopping)
             (error "Illegal state: ~a" %state))
            (t
             (progn
               (set-stopping life-cycle)
               (call-next-method)
               (set-stopped life-cycle))))
        (t (c)
          (set-failed life-cycle c)
          (error c))))))

(defun running-p (life-cycle)
  (with-slots (%state) life-cycle
    (case %state
      ((:started :starting)
       t)
      (t nil))))

(defun started-p (life-cycle)
  (eq :started (slot-value life-cycle '%state)))

(defun starting-p (life-cycle)
  (eq :starting (slot-value life-cycle '%state)))

(defun stopping-p (life-cycle)
  (eq :stopping (slot-value life-cycle '%state)))

(defun stopped-p (life-cycle)
  (eq :stopped (slot-value life-cycle '%state)))

(defun failed-p (life-cycle)
  (eq :failed (slot-value life-cycle '%state)))

;; (log:config :debug)

;; Handler

(defclass handler (life-cycle)
  ((%server :initform nil)))

(defgeneric handle (handler target request response))

(defmethod start ((handler handler))
  (log:debug "starting ~a" handler)
  (unless (slot-value handler '%server)
    (log:warn "No server set for ~a" handler)))

(defmethod stop ((handler handler))
  (log:debug "stopping ~a" handler))


;; Connector

(defclass connector ()
  ())

(defgeneric open (connector))
(defgeneric close (connector))

;; Server
                 
(defclass server (handler)
  ((%thread-pool :initform nil)
   (%handler :initform nil)
   (%connectors :initform nil)
   (%dry-run-p :initform nil)
  (:documentation "
  This class is the main class for the HTTP server.
  It aggregates Connectors (HTTP request receivers) and request Handlers.
  The server is itself a handler and a ThreadPool.  Connectors use the
  ThreadPool methods to run jobs that will eventually call the handle method.
"))

(defparameter +version+ "0.1.0")

(defparameter +version-stable-p+ nil)

(defmethod start ((server server))

  (handler-case
      (progn
        (unless (slot-value server '%dry-run-p)
          (dolist (connector (slot-value server '%connectors))
            (handler-case
                (open connector)
              (t ()
                (error "TODO: handle errors")))))
        (log:info "Letty ~a" +version+)

        (unless +version-stable-p+
          (log:warn "THIS IS NOT A STABLE RELEASE! DO NOT USE IN PRODUCTION!"))

        (dolist (connector (slot-value server '%connectors))
          (handler-case
              (start connector)
            (t ()
              (error "TODO: handle errors")
              (dolist (connector (slot-value server '%connectors))
                (stop connector))))))
    
    (t (c)
      (dolist (connector (slot-value server '%connectors))
        (handler-case
            (close connector)
          (t ()
            (erorr "TODO handle errors")))))))
  
  

(defmethod stop ((server server))
  (log:info "Stopped ~a" server))

(defmethod join ((server server))
  (error "TODO"))


  
