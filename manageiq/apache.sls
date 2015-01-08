{% from "manageiq/map.jinja" import miq_map with context %}

apache:
  pkg.installed:
    - name: {{ miq_map.apacheserver }}
  service.running:
    - name: {{ miq_map.apacheservice }}
    - enable: True

# The following states are inert by default and can be used by other states to
# trigger a restart or reload as needed.
apache-reload:
  module.wait:
    - name: service.reload
    - m_name: {{ miq_map.apacheservice }}

apache-restart:
  module.wait:
    - name: service.restart
    - m_name: {{ miq_map.apacheservice }}
