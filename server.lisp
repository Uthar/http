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

;; Connection factory

(defclass http-connection-factory ()
  ())

;; Connector

(defclass connector ()
  ())

(defgeneric open (connector))
(defgeneric close (connector))

;; AbstractConnector

(defclass abstract-connector (life-cycle)
  ((%default-protocol :initform nil)
   (%acceptors :initform nil)
   (%lock :initform (bt:make-lock))
   (%accepting :initform t))
  (:default-initargs
   :acceptors 1))

;; TODO(kasper) implement
(defun get-cpu-count ()
  4)

(defclass acceptor ()
  ((%connector :initform nil)
   (%id :initform nil)
   (%name :initform nil)))

(defmacro while (expr &body body)
  `(loop while ,expr do ,@body))

(defun accept (id)
  ;; TODO (kasper) implement)

(defmethod run ((acceptor acceptor))
  (let* ((thread (bt:current-thread))
         (name (bt:thread-name thread)))
    ;; Can't set thread name in Common Lisp :-(
    ;; (setf name (format nil "~a-acceptor~d@~x-~a"
    ;;                    name %id (sxhash acceptor) acceptor

    ;; TODO(kasper) handle priority

    (with-slots (%connector %id)
        acceptor
      (with-slots (%lock %acceptors %accepting)
          %connector
        (bt:with-lock-held (%lock)
          (setf (aref %acceptors %id) thread))
        (unwind-protect
             (catch 'break
               (while (running-p %connector)
                 (catch 'continue
                   (bt:with-lock-held (%lock)
                     (when (and (not %accepting)
                                (running-p %connector))
                       (throw 'continue nil))))
                 (handler-case
                     (accept %id)
                   (t (x)
                     (unless (handle-accept-failure x)
                       (throw 'break nil))))))
          
          ;; TODO(kasper) clean up thread
          nil)))))
              
            
                    
                
    
                       
  
(defmethod initialize-instance :after
    ((connector abstract-connector) &key acceptors)
  (let ((cores (get-cpu-count)))
    (with-slots (%acceptors)
        connector
      (when (minusp acceptors)
        (setf acceptors (max 1 (min 4 (/ cores 8)))))
      (when (> acceptors cores)
        (warn "Acceptors should be <= available processors: ~a" connector))
      (setf %acceptors (make-array acceptors)))))

(defmethod start ((connector abstract-connector))
  (with-slots (%default-protocol %default-connection-factory)
      connector
    (unless %default-protocol
      (error "No default protocol for ~a" connector))
    (setf %default-connection-factory
          (get-connection-factory %default-protocol))
    (unless %default-connection-factory
      (error "No protocol factory for default protocol ~a" %default-protocol))
    ;; TODO(kasper) TLS
    ;; (when-let ((ssl (get-connection-factory :ssl-connection-factory)))
    
  

;; The {@link Executor} service is used to run all active tasks needed by this
;; connector such as accepting connections * or handle HTTP requests. The
;; default is to use the {@link Server#getThreadPool()} as an executor.
;;
;; I.E. use %thread-pool of the server

(defclass server-connector (connector)
  ((%port :initform 0))
  (:documentation ""))

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


  
(defclass abstract-foo ()
  (thing))

(defmethod initialize-instance :around ((foo abstract-foo) &key)
  (print "around abstract foo")
  (call-next-method))

(defmethod initialize-instance :before ((foo abstract-foo) &key)
  (print "before abstract foo"))

(defmethod initialize-instance :after ((foo abstract-foo) &key)
  (print "after abstract foo"))

(defclass foo (abstract-foo)
  ())

(defmethod initialize-instance :around ((foo foo) &key)
  (print "around normal foo")
  (call-next-method))

(defmethod initialize-instance :before ((foo foo) &key)
  (print "before normal foo"))

(defmethod initialize-instance :after ((foo foo) &key)
  (print "after normal foo"))

(progn
  (make-instance 'foo)
  (terpri))
