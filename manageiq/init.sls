{% import "manageiq/settings.sls" as miq_settings with context %}
{% from "manageiq/map.jinja" import miq_map with context %}

miq-pkgs:
  pkg.installed:
    - pkgs:
      - {{ miq_map.git }}
      - {{ miq_map.sudo }}
      - {{ miq_map.libxml2devel }}
      - {{ miq_map.libxml2 }}
      - {{ miq_map.libxslt }}
      - {{ miq_map.libxsltdevel }}
      - {{ miq_map.postgresqldevel }}
      - {{ miq_map.postgresqlserver }}
      - {{ miq_map.memcached }}
      - {{ miq_map.apache }}
      - {{ miq_map.nettools }}
{% if miq_settings.enviroment = "production" %}
      - {{ miq_map.nodejs }}
{% endif %}

ruby-pkgs:
  pkg.installed:
    - pkgs:
      - {{ miq_map.rubydevel }}
      - {{ miq_map.ruby }}
      - {{ miq_map.rubygems }}
      - {{ miq_map.rubygembundler }}
    - require:
      - pkg: miq-pkgs


memcached:
  service.running:
    - enable: True
    - require:
      - pkg: miq-pkgs

postgres-init:
  cmd.run:
    - name: sudo service postgresql initdb
    - unless: test -f /var/lib/pgsql/data/pg_hba.conf
    - require:
      - pkg: miq-pkgs

postgresql:
  service.running:
    - enable: True
    - require:
      - pkg: miq-pkgs
      - cmd: postgres-init
      - file: /var/lib/pgsql/data/postgresql.conf
      - file: /var/lib/pgsql/data/pg_hba.conf

root:
  postgres_user.present:
    - createdb: True
    - password: {{ miq_settings.prod_root_password }}
    - encrypted: False
    - login: True
    - require:
      - service: postgresql

vmdb_production:
  postgres_database.present:
    - db_user: root
    - password: {{ miq_settings.prod_root_password }}
    - require:
      - service: postgresql
      - postgres_user: root

vmdb_development:
  postgres_database.present:
    - db_user: root
    - password: {{ miq_settings.devel_root_password }}
    - require:
      - service: postgresql
      - postgres_user: root

/var/lib/pgsql/data/pg_hba.conf:
  file.managed:
    - source: salt://manageiq/pg_hba.conf
    - require:
      - cmd: postgres-init

/var/lib/pgsql/data/postgresql.conf:
  file.managed:
    - source: salt://manageiq/postgresql.conf
    - require:
      - cmd: postgres-init

{{ miq_settings.root_dir }}:
  file.directory:
    - makedirs: True

git_clone:
  git.latest:
    - name: https://github.com/ManageIQ/manageiq.git
    - target: {{ miq_settings.root_dir }}
    - require:
      - file: {{ miq_settings.root_dir }}

{% if '7' in grains['osmajorrelease'] %}
firewalld:
  cmd.run:
    - name: firewall-cmd --zone=public --add-port=3000/tcp --permanent ; firewall-cmd --reload
    - unless: firewall-cmd --zone=public --query-port=3000/tcp
{% endif %}

iptables:
  cmd.run:
{% if '7' in grains['osmajorrelease'] %}
    - name: firewall-cmd --zone=public --add-forward-port=port=80:proto=tcp:toport=3000 --permanent ; firewall-cmd --reload
    - unless: firewall-cmd --zone=public --query-forward-port=port=80:proto=tcp:toport=3000
{% else %}
    - name: iptables -A PREROUTING -t nat -i eth0 -p tcp --dport 80 -j REDIRECT --to-port 3000 && service iptables save
    - unless: iptables -C PREROUTING -t nat -i eth0 -p tcp --dport 80 -j REDIRECT --to-port 3000
{% endif %}

 
bundler:
  cmd.run:
    - name: cd {{ miq_settings.root_dir }}/vmdb ; bundle install --without qpid
    - require:
      - git: git_clone
      - service: memcached
    - unless: test -d {{ miq_settings.root_dir }}/vmdb/bin

shared_objects:
  cmd.run:
    - name: cd {{ miq_settings.root_dir }} ; vmdb/bin/rake build:shared_objects
    - require:
      - git: git_clone
      - cmd: bundler
      - service: memcached
    - unless: test -f {{ miq_settings.root_dir }}/lib/disk/modules/MiqBlockDevOps.so

{% if miq_settings.enviroment = "production" %}
production_build:
  cmd.run:
    - name: cd {{ miq_settings.root_dir }}/vmdb ; RAILS_ENV=production rake evm:compile_assets
    - require:
      - git: git_clone
      - cmd: bundler
      - cmd: shared_objects
      - service: memcached
      - service: postgresql
{% endif %}

database_setup:
  cmd.run:
    - name: cd {{ miq_settings.root_dir }}/vmdb ; bin/rake db:migrate
    - require:
      - git: git_clone
      - cmd: bundler
      - cmd: shared_objects
      - service: memcached
      - service: postgresql
    - unless: test=$(psql vmdb_development -A -0 -z -q -t -c "select count(*) from information_schema.tables;") ; test $test -ge 300

{% if '7' in grains['osmajorrelease'] %}
/usr/lib/systemd/system/manageiq.service:
  file.managed:
    - source: salt://manageiq/manageiq.service
    - template: jinja
    - context:
      root_dir: {{ miq_settings.root_dir }}
{% else %}
/etc/init.d/manageiq:
  file.managed:
    - source: salt://manageiq/manageiq.init
    - mode: 775
    - context:
      root_dir: {{ miq_settings.root_dir }}
{% endif %}

/var/log/manageiq:
  file.symlink:
    - target: {{ miq_settings.root_dir }}/vmdb/log

manageiq:
  service.running:
    - enable: True

#The default username and password is username : admin and password : smartvm
