#!/bin/sh

openssl dsaparam -outform PEM -out openid.param -genkey 1024
openssl dsa -in openid.param -pubout -out openid-public.pem
openssl dsa -in openid.param         -out openid-private.pem
rm openid.param
