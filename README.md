# mailserver

## What Is this ?

A containerized, production ready, full featured, full ssl secured (for free) mailserver almost zero-config, easy to deploy and reproduce without lost data. (A dream ?)

## What I take ?

* Postfix/dovecot web server ready to setup to your email clients
* Webmail endpoint ssl secured (roundcube)
* Admin endpoint ssl secures (postfix admin), ready for multiple domains
* Endpoints to use with your email clients imap smpt (NOT pop)
* All SSL secured with Let's Encrypt auto renew

## Components

Linux, Postfix, Dovecot, spamassassin, MySQL, Roundcube, Postfix Admin, Caddyserver, acme.sh

## Prerequisites

* Docker host with static ip
* Domain name
* Ability to write dns entries (dns server, or use the dns api of vultr, digitalocean...)

## Usage

Write dns entries and restart the dns server, if you use one

```

mail.company.com.	3600 IN	A (docker host ip)
admin.company.com. 3600 IN	A (docker host ip)
imap.company.com.	3600 IN	A (docker host ip)
smtp.company.com.	3600 IN	A (docker host ip)

company.com.		3600 IN MX 10 smtp.company.com.

```
You can use multiple domains just write an mx record for each one indicating your smtp server

```
compadyproduct.com.		3600 IN MX 10 smtp.company.com.
```

Create a directory to your host for persistent data: accounts, emails, databases and logs, having this folder you can reproduce your server without loss anyhing. (accounts, data...) 

```
mkdir -p /data/ 
```


Start docker.
```
docker run  -d \
\
-v /data/log:/var/log \
-v /data/vmail:/var/vmail \
-v /data/mysql:/var/lib/mysql \
-v /data/ssl:/ssl \
-v /data/caddy:/root/.caddy \
\
-p 25:25 \
-p 80:80 \
-p 143:143 \
-p 443:443 \
-p 465:465 \
-p 993:993 \
\
-e "PADMIN=admin" \
-e "PADMP=password" \
-e "WEBMAIL_URL=mail.company.com" \
-e "ADMIN_URL=admin.company.com" \
-e "SMTP_URL=smtp.company.com" \
-e "IMAP_URL=imap.company.com" \
-e "POSTMASTER=postmaster@company.com" \
-e "ACME_EMAIL=admins@email.com" \
-e "ACME_STAGING=true" \
konhondros/mailserver
```
> If your server is for production remove `-e "ACME_STAGING=true"` to get valid certificates from letsencrypt, NOT deploy much times the image without `ACME_STAGING=true` because lets encrypt will hit rate limit.

After running container, you can access admin panel here - https://admin.company.com, use login and password defined within docker start, with variables PADMP abd PADMIN, change it after first use, then you must add domains in `Domain List > New Domain` and create accounts in `Virtual List > Add Mailbox`

Webmail can be accessed here - https://mail.company.com, using accounts created with admin panel. Or you can use your mail client via ports: smtp, imap, imaps, smtps.

> As username use `full email address` either webmail or email clients

This repository is based on https://github.com/RomanGorokhov/postfix-roundcube

## Feel free to contribute!