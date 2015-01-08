{% set p  = salt['pillar.get']('manageiq', {}) %}

#ManageIQ SETTINGS
{% set root_dir = p.get('root_dir', '/var/www/miq') %}
{% set environment =  p.get('environment', 'production') %}

#DATABASE SETTINGS
{% set db = p.get('postgres', {}) %}
{% set prod_root_password = db.get('prod_root_password', 'smartvm') %}
{% set devel_root_password = db.get('devel_root_password', 'smartvm') %}
