;; Copyright 2011-2012 Ryan Culpepper
;; Released under the terms of the LGPL version 3 or later.
;; See the file COPYRIGHT for details.

#lang racket/base
(require racket/class
         racket/string
         net/url
         web-server/http
         web-server/http/bindings
         web-server/templates
         "net.rkt"
         "oauth2.rkt"
         web-server/servlet-env)
(provide oauth2/request-auth-code/browser)

#|
TO DO:
 - generalize port from 8000
 - try oauth2/request-access/browser again
|#

(define (oauth2/request-auth-code/browser auth-server client scopes)
  (let ([oauth2 (new oauth2%
                     (auth-server auth-server)
                     (client client))])
    (let ([auth-code (request-auth-code/web oauth2 scopes)])
      (send oauth2 acquire-token/auth-code!
            auth-code
            #:redirect-uri "http://localhost:8000/oauth2/response"
            #:who 'oauth2/request-access/web)
      oauth2)))

(define (request-auth-code/web oauth2 scopes
                               #:who [who 'request-access/web])
  (let ([chan (make-channel)]
        [server-cust (make-custodian)])
    (parameterize ((current-custodian server-cust))
      (thread
       (lambda ()
         (serve/servlet (make-servlet oauth2 scopes chan)
                        #:launch-browser? #t
                        #:quit? #t
                        #:banner? #f
                        #:port 8000
                        #:servlet-path "/oauth2/init"
                        #:servlet-regexp #rx"^/oauth2/"
                        #:extra-files-paths null))))
    (begin0 (channel-get chan)
      (custodian-shutdown-all server-cust))))

(define (make-servlet oauth2 scopes chan)
  (lambda (req)
    (let ([path (string-join (map path/param-path (url-path (request-uri req))) "/")])
      (cond [(equal? path "oauth2/init")
             (redirect-to
              (let ([auth-server (send oauth2 get-auth-server)]
                    [client (send oauth2 get-client)])
                (send auth-server get-auth-request-url
                      #:client client
                      #:scopes scopes
                      #:redirect-uri "http://localhost:8000/oauth2/response")))]
            [(equal? path "oauth2/response")
             (let ([bindings (request-bindings/raw req)])
               (cond [(bindings-assq #"code" bindings)
                      => (lambda (code-b)
                           (channel-put chan
                                        (bytes->string/utf-8
                                         (binding:form-value code-b)))
                           (response/full
                            200 #"Okay"
                            (current-seconds) TEXT/HTML-MIME-TYPE
                            null
                            (list (string->bytes/utf-8
                                   (include-template "static-got-auth-code.html")))))]
                     [(bindings-assq #"error" bindings)
                      => (lambda (err-b)
                           (error "Failed: ~s" (binding:form-value err-b)))]
                     [else (error "Bad response!")]))]
            [else (error "Invalid URL: ~s" path)]))))
