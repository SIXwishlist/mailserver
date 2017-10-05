#!/bin/sh

# Load acme.sh env file to sh
. ./root/.acme.sh/acme.sh.env

_install_caddyfile() {
  touch /etc/Caddyfile
  
  mkdir -p /var/www/$3 && echo "<h2>Restricted</h2>" > /var/www/$3/index.html
  mkdir -p /var/www/$4 && echo "<h2>Restricted</h2>" > /var/www/$4/index.html
  chown -R www-data /var/www/

  cat > /etc/Caddyfile << EOT
  https://$1 {
      fastcgi / unix:/var/run/php5-fpm.sock php
      root /var/www/html/roundcubemail
  }

  https://$2 {
      fastcgi / unix:/var/run/php5-fpm.sock php
      root /var/www/html/postfixadmin
  }

  http://$3 {
      root /var/www/$3
  }

  http://$4 {
      root /var/www/$4
  }
EOT
}

_start_caddy() {
  command="caddy -conf=/etc/Caddyfile -email=$ACME_EMAIL -log=/var/log/caddy/caddy.log"

  if [ "$ACME_STAGING" = true ]; then
    command="$command -ca=https://acme-staging.api.letsencrypt.org/directory"
  fi
  eval $command&
}

_install_dovecot_conf() {
  mkdir -p /ssl/$IMAP_URL

  # Issue self signed for beginning
  openssl req -nodes -x509 -newkey rsa:4096 -keyout /ssl/$IMAP_URL/cert.key -out /ssl/$IMAP_URL/cert.crt -subj "/O=Mail Server For You/OU=Email Services/CN=$IMAP_URL"

  postmaster_address="postmaster@$IMAP_URL"
  
  if [ $POSTMASTER ]; then
    postmaster_address=$POSTMASTER
  fi

  cat > /etc/dovecot/dovecot.conf << EOT
auth_mechanisms = plain login
disable_plaintext_auth = yes
mail_gid = mail
mail_location = maildir:/var/vmail/%d/%n
mail_uid = vmail
namespace inbox {
  inbox = yes
  location =
  mailbox Drafts {
    special_use = \Drafts
  }
  mailbox Junk {
    special_use = \Junk
  }
  mailbox Sent {
    special_use = \Sent
  }
  mailbox "Sent Messages" {
    special_use = \Sent
  }
  mailbox Trash {
    special_use = \Trash
  }
  prefix =
}
passdb {
  args = /etc/dovecot/dovecot-sql.conf.ext
  driver = sql
}
postmaster_address = $postmaster_address
protocols = "imap lmtp"
service auth {
  unix_listener /var/spool/postfix/private/auth {
    group = postfix
    mode = 0666
    user = postfix
  }
  unix_listener auth-userdb {
    group = mail
    mode = 0666
    user = vmail
  }
}
ssl_cert = </ssl/$IMAP_URL/cert.crt
ssl_key = </ssl/$IMAP_URL/cert.key

ssl_cipher_list = ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-AES256-GCM-SHA384:DHE-RSA-AES128-GCM-SHA256:DHE-DSS-AES128-GCM-SHA256:kEDH+AESGCM:ECDHE-RSA-AES128-SHA256:ECDHE-ECDSA-AES128-SHA256:ECDHE-RSA-AES128-SHA:ECDHE-ECDSA-AES128-SHA:ECDHE-RSA-AES256-SHA384:ECDHE-ECDSA-AES256-SHA384:ECDHE-RSA-AES256-SHA:ECDHE-ECDSA-AES256-SHA:DHE-RSA-AES128-SHA256:DHE-RSA-AES128-SHA:DHE-DSS-AES128-SHA256:DHE-RSA-AES256-SHA256:DHE-DSS-AES256-SHA:DHE-RSA-AES256-SHA:AES128-GCM-SHA256:AES256-GCM-SHA384:AES128-SHA256:AES256-SHA256:AES128-SHA:AES256-SHA:AES:CAMELLIA:DES-CBC3-SHA:!aNULL:!eNULL:!EXPORT:!DES:!RC4:!MD5:!PSK:!aECDH:!EDH-DSS-DES-CBC3-SHA:!EDH-RSA-DES-CBC3-SHA:!KRB5-DES-CBC3-SHA
ssl_dh_parameters_length = 2048
ssl_prefer_server_ciphers = yes
ssl_protocols = !SSLv2 !SSLv3
userdb {
  args = /etc/dovecot/dovecot-sql.conf.ext
  driver = sql
}
EOT
}

_install_postfix_conf() {
  mkdir -p /ssl/$SMTP_URL

  # Issue self signed for beginning
  openssl req -nodes -x509 -newkey rsa:4096 -keyout /ssl/$SMTP_URL/cert.key -out /ssl/$SMTP_URL/cert.crt -subj "/O=Mail Server For You/OU=Email Services/CN=$SMTP_URL"

  cat > /etc/postfix/main.cf << EOT
# The first text sent to a connecting process.
smtpd_banner = \$myhostname ESMTP \$mail_name
biff = no
# appending .domain is the MUA's job.
append_dot_mydomain = no
readme_directory = no

# ---------------------------------
# SASL parameters
# ---------------------------------

# Use Dovecot to authenticate.
smtpd_sasl_type = dovecot
# Referring to /var/spool/postfix/private/auth
smtpd_sasl_path = private/auth
smtpd_sasl_auth_enable = yes
broken_sasl_auth_clients = yes
smtpd_sasl_security_options = noanonymous
smtpd_sasl_local_domain =
smtpd_sasl_authenticated_header = yes

# ---------------------------------
# TLS parameters
# ---------------------------------

# The default snakeoil certificate. Comment if using a purchased
# SSL certificate.
#smtpd_tls_cert_file=/etc/ssl/certs/ssl-cert-snakeoil.pem
#smtpd_tls_key_file=/etc/ssl/private/ssl-cert-snakeoil.key

# Uncomment if using a purchased SSL certificate.
smtpd_tls_cert_file=/ssl/$SMTP_URL/cert.crt
smtpd_tls_key_file=/ssl/$SMTP_URL/cert.key

# The snakeoil self-signed certificate has no need for a CA file. But
# if you are using your own SSL certificate, then you probably have
# a CA certificate bundle from your provider. The path to that goes
# here.
# smtpd_tls_CAfile=/etc/ssl/certs/ca-bundle.crt

# Ensure we're not using no-longer-secure protocols.
smtpd_tls_mandatory_protocols=!SSLv2,!SSLv3

smtp_tls_note_starttls_offer = yes
smtpd_tls_loglevel = 1
smtpd_tls_received_header = yes
smtpd_tls_session_cache_timeout = 3600s
tls_random_source = dev:/dev/urandom
#smtpd_tls_session_cache_database = btree:\${data_directory}/smtpd_scache
#smtp_tls_session_cache_database = btree:\${data_directory}/smtp_scache

# Note that forcing use of TLS is going to cause breakage - most mail servers
# don't offer it and so delivery will fail, both incoming and outgoing. This is
# unfortunate given what various governmental agencies are up to these days.
#
# Enable (but don't force) all incoming smtp connections to use TLS.
smtpd_tls_security_level = may
# Enable (but don't force) all outgoing smtp connections to use TLS.
smtp_tls_security_level = may

# See /usr/share/doc/postfix/TLS_README.gz in the postfix-doc package for
# information on enabling SSL in the smtp client.

# ---------------------------------
# TLS Updates relating to Logjam SSL attacks.
# See: https://weakdh.org/sysadmin.html
# ---------------------------------

smtpd_tls_exclude_ciphers = aNULL, eNULL, EXPORT, DES, RC4, MD5, PSK, aECDH, EDH-DSS-DES-CBC3-SHA, EDH-RSA-DES-CDC3-SHA, KRB5-DE5, CBC3-SHA
smtpd_tls_dh1024_param_file = /etc/ssl/private/dhparams.pem

# ---------------------------------
# SMTPD parameters
# ---------------------------------

# Uncomment the next line to generate "delayed mail" warnings
#delay_warning_time = 4h
# will it be a permanent error or temporary
unknown_local_recipient_reject_code = 450
# how long to keep message on queue before return as failed.
# some have 3 days, I have 16 days as I am backup server for some people
# whom go on holiday with their server switched off.
maximal_queue_lifetime = 7d
# max and min time in seconds between retries if connection failed
minimal_backoff_time = 1000s
maximal_backoff_time = 8000s
# how long to wait when servers connect before receiving rest of data
smtp_helo_timeout = 60s
# how many address can be used in one message.
# effective stopper to mass spammers, accidental copy in whole address list
# but may restrict intentional mail shots.
smtpd_recipient_limit = 16
# how many error before back off.
smtpd_soft_error_limit = 3
# how many max errors before blocking it.
smtpd_hard_error_limit = 12

# This next set are important for determining who can send mail and relay mail
# to other servers. It is very important to get this right - accidentally producing
# an open relay that allows unauthenticated sending of mail is a Very Bad Thing.
#
# You are encouraged to read up on what exactly each of these options accomplish.

# Requirements for the HELO statement
smtpd_helo_restrictions = permit_mynetworks, warn_if_reject reject_non_fqdn_hostname, reject_invalid_hostname, permit
# Requirements for the sender details
smtpd_sender_restrictions = permit_sasl_authenticated, permit_mynetworks, warn_if_reject reject_non_fqdn_sender, reject_unknown_sender_domain, reject_unauth_pipelining, permit
# Requirements for the connecting server
smtpd_client_restrictions = reject_rbl_client sbl.spamhaus.org, reject_rbl_client blackholes.easynet.nl
# Requirement for the recipient address. Note that the entry for
# "check_policy_service inet:127.0.0.1:10023" enables Postgrey.
smtpd_recipient_restrictions = reject_unauth_pipelining, permit_mynetworks, permit_sasl_authenticated, reject_non_fqdn_recipient, reject_unknown_recipient_domain, reject_unauth_destination, permit
smtpd_data_restrictions = reject_unauth_pipelining
# This is a new option as of Postfix 2.10, and is required in addition to
# smtpd_recipient_restrictions for things to work properly in this setup.
smtpd_relay_restrictions = reject_unauth_pipelining, permit_mynetworks, permit_sasl_authenticated, reject_non_fqdn_recipient, reject_unknown_recipient_domain, reject_unauth_destination, permit

# require proper helo at connections
smtpd_helo_required = yes
# waste spammers time before rejecting them
smtpd_delay_reject = yes
disable_vrfy_command = yes

# ---------------------------------
# General host and delivery info
# ----------------------------------

myhostname = $SMTP_URL
myorigin = /etc/hostname
# Some people see issues when setting mydestination explicitly to the server
# subdomain, while leaving it empty generally doesn't hurt. So it is left empty here.
# mydestination = mail.example.com, localhost
mydestination =
# If you have a separate web server that sends outgoing mail through this
# mailserver, you may want to add its IP address to the space-delimited list in
# mynetworks, e.g. as 10.10.10.10/32.
mynetworks = 127.0.0.0/8 [::ffff:127.0.0.0]/104 [::1]/128
mailbox_size_limit = 0
recipient_delimiter = +
inet_interfaces = all
mynetworks_style = host

# This specifies where the virtual mailbox folders will be located.
virtual_mailbox_base = /var/vmail
# This is for the mailbox location for each user. The domainaliases
# map allows us to make use of Postfix Admin's domain alias feature.
virtual_mailbox_maps = mysql:/etc/postfix/mysql_virtual_mailbox_maps.cf, mysql:/etc/postfix/mysql_virtual_mailbox_domainaliases_maps.cf
# and their user id
virtual_uid_maps = static:150
# and group id
virtual_gid_maps = static:8
# This is for aliases. The domainaliases map allows us to make
# use of Postfix Admin's domain alias feature.
virtual_alias_maps = mysql:/etc/postfix/mysql_virtual_alias_maps.cf, mysql:/etc/postfix/mysql_virtual_alias_domainaliases_maps.cf
# This is for domain lookups.
virtual_mailbox_domains = mysql:/etc/postfix/mysql_virtual_domains_maps.cf

# ---------------------------------
# Integration with other packages
# ---------------------------------------

# Tell postfix to hand off mail to the definition for dovecot in master.cf
virtual_transport = dovecot
dovecot_destination_recipient_limit = 1

# Use amavis for virus and spam scanning
#content_filter = amavis:[127.0.0.1]:10024

# ---------------------------------
# Header manipulation
# --------------------------------------

# Getting rid of unwanted headers. See: https://posluns.com/guides/header-removal/
#header_checks = regexp:/etc/postfix/header_checks
# getting rid of x-original-to
enable_original_recipient = no
EOT
}

_install_certs() {
  acme.sh --upgrade --log

  command1="acme.sh --issue -d $SMTP_URL -w /var/www/$SMTP_URL"
  command2="acme.sh --issue -d $IMAP_URL -w /var/www/$IMAP_URL"
  
  if [ "$ACME_STAGING" = true ]; then
    command1="$command1 --test"
    command2="$command2 --test"
  fi

  eval $command1 
  eval $command2
  
  acme.sh --install-cert -d $SMTP_URL --fullchain-file /ssl/$SMTP_URL/cert.crt --key-file /ssl/$SMTP_URL/cert.key --reloadcmd "/etc/init.d/postfix reload"
  acme.sh --install-cert -d $IMAP_URL --fullchain-file /ssl/$IMAP_URL/cert.crt --key-file /ssl/$IMAP_URL/cert.key --reloadcmd "doveadm reload"
}

chown -R vmail /var/vmail
chown -R www-data /var/www/html/
chown -R mysql /var/lib/mysql

chown :syslog /var/log/
chmod 775 /var/log/

mkdir -p /var/log/caddy /var/log/mysql

if [ ! -d "/var/lib/mysql/mysql" ];
then
  /usr/bin/mysql_install_db
fi

/etc/init.d/mysql start

PSSW=`doveadm pw -s MD5-CRYPT -p $PADMP | sed 's/{MD5-CRYPT}//'`

if [ ! -d "/var/lib/mysql/mail" ]; 
then
  mysql < /root/roundcube_postfixadmin.sql
  mysql -e "insert into admin values('$PADMIN','$PSSW',1,'2016-03-02 15:23:14','2016-03-03 16:24:44',1);insert into domain_admins values('$PADMIN', 'ALL', NOW(), 1)" mail;
fi


# Install Postfix configuration file
_install_postfix_conf

# Install Dovecot configuration file
_install_dovecot_conf

/etc/init.d/postfix start
/etc/init.d/rsyslog start
/etc/init.d/php5-fpm start
/etc/init.d/spamassassin start
/usr/sbin/dovecot


# Install the Caddyfile
_install_caddyfile $WEBMAIL_URL $ADMIN_URL $SMTP_URL $IMAP_URL

# Start the caddy web server
_start_caddy

# Start cron daemon
cron

# Wait 20 seconds to be ready the webserver
# and issue the certificates
sleep 10
_install_certs

# Let the script live
# if the script is terminated the docker will be terminated too
tail -f /dev/null