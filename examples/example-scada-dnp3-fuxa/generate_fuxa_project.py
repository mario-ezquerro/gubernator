#!/usr/bin/env python3
"""
generate_fuxa_project.py - Builds the pre-configured FUXA SCADA Project
Creates both project.fuxap (JSON) and project.fuxap.db (SQLite database)
for instant zero-touch initialization of the FUXA container.
"""

import json
import os
import sqlite3
import sys

TARGET_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), "fuxa-appdata"))
os.makedirs(TARGET_DIR, exist_ok=True)

DEV_ID = "dnp3_mqtt"
DEV_NAME = "DNP3_MQTT_Gateway"

# 1. Tags definition
tags = {
    # Substation Alpha Tags
    "sub_voltage": {
        "id": "sub_voltage",
        "name": "Substation Busbar Voltage",
        "type": "number",
        "address": "scada/dnp3/substation_alpha/voltage_kv",
        "description": "Grid Voltage 25 kV"
    },
    "sub_current": {
        "id": "sub_current",
        "name": "Substation Feeder Current",
        "type": "number",
        "address": "scada/dnp3/substation_alpha/current_a",
        "description": "Feeder Load Current (A)"
    },
    "sub_power": {
        "id": "sub_power",
        "name": "Substation Active Power",
        "type": "number",
        "address": "scada/dnp3/substation_alpha/power_mw",
        "description": "Active Power (MW)"
    },
    "sub_reactive": {
        "id": "sub_reactive",
        "name": "Substation Reactive Power",
        "type": "number",
        "address": "scada/dnp3/substation_alpha/power_mvar",
        "description": "Reactive Power (MVAr)"
    },
    "sub_freq": {
        "id": "sub_freq",
        "name": "Grid Frequency",
        "type": "number",
        "address": "scada/dnp3/substation_alpha/freq_hz",
        "description": "Grid Frequency (Hz)"
    },
    "sub_trafo_temp": {
        "id": "sub_trafo_temp",
        "name": "Power Transformer Temp",
        "type": "number",
        "address": "scada/dnp3/substation_alpha/trafo_temp",
        "description": "Transformer Temp (°C)"
    },
    "sub_breaker_status": {
        "id": "sub_breaker_status",
        "name": "Circuit Breaker 52-1 Status",
        "type": "number",
        "address": "scada/dnp3/substation_alpha/breaker_status",
        "description": "1=Closed/Live, 0=Tripped/Open"
    },
    "sub_breaker_cmd": {
        "id": "sub_breaker_cmd",
        "name": "Breaker 52-1 Command",
        "type": "raw",
        "address": "scada/dnp3/control/substation_alpha/breaker",
        "description": "Trip/Close Breaker via DNP3 CROB"
    },
    "sub_oc_alarm": {
        "id": "sub_oc_alarm",
        "name": "Overcurrent Trip Alarm 50/51",
        "type": "number",
        "address": "scada/dnp3/substation_alpha/alarm_overcurrent",
        "description": "Relay 50/51 Trip Status"
    },

    # Solar PV Farm Beta Tags
    "sol_generation": {
        "id": "sol_generation",
        "name": "Solar Active Power",
        "type": "number",
        "address": "scada/dnp3/solar_farm/generation_kw",
        "description": "Photovoltaic Generation (kW)"
    },
    "sol_irradiance": {
        "id": "sol_irradiance",
        "name": "Solar Irradiance",
        "type": "number",
        "address": "scada/dnp3/solar_farm/irradiance_wm2",
        "description": "Solar Irradiance (W/m²)"
    },
    "sol_dc_voltage": {
        "id": "sol_dc_voltage",
        "name": "Solar DC String Voltage",
        "type": "number",
        "address": "scada/dnp3/solar_farm/dc_voltage_v",
        "description": "DC Bus Voltage (V)"
    },
    "sol_dc_current": {
        "id": "sol_dc_current",
        "name": "Solar DC Array Current",
        "type": "number",
        "address": "scada/dnp3/solar_farm/dc_current_a",
        "description": "DC Current (A)"
    },
    "sol_inv_temp": {
        "id": "sol_inv_temp",
        "name": "Solar Inverter Temp",
        "type": "number",
        "address": "scada/dnp3/solar_farm/inverter_temp",
        "description": "IGBT Temperature (°C)"
    },
    "sol_ambient_temp": {
        "id": "sol_ambient_temp",
        "name": "Ambient Temperature",
        "type": "number",
        "address": "scada/dnp3/solar_farm/ambient_temp",
        "description": "Ambient Temp (°C)"
    },
    "sol_inv_status": {
        "id": "sol_inv_status",
        "name": "Solar Inverter Status",
        "type": "number",
        "address": "scada/dnp3/solar_farm/inverter_running",
        "description": "1=Exporting, 0=Curtailed"
    },
    "sol_inv_cmd": {
        "id": "sol_inv_cmd",
        "name": "Solar Inverter Command",
        "type": "raw",
        "address": "scada/dnp3/control/solar_farm/inverter",
        "description": "Curtail/Enable Inverter via DNP3 CROB"
    }
}

device = {
    "id": DEV_ID,
    "name": DEV_NAME,
    "type": "MQTT",
    "enabled": True,
    "property": {
        "address": "mqtt://mqtt:1883",
        "timeout": 10000
    },
    "tags": tags
}

# 2. HMI View Items (Values, Semaphores, Buttons)
items = {
    # Substation Voltage
    "VAL_sub_v": {
        "id": "VAL_sub_v",
        "type": "svg-ext-value",
        "name": "sub_voltage",
        "label": "Value",
        "property": {
            "events": [],
            "variable": "sub_voltage",
            "variableId": f"{DEV_NAME}^~^sub_voltage",
            "variableSrc": DEV_NAME,
            "ranges": [{"type": "unit", "text": " kV"}]
        }
    },
    # Substation Current
    "VAL_sub_i": {
        "id": "VAL_sub_i",
        "type": "svg-ext-value",
        "name": "sub_current",
        "label": "Value",
        "property": {
            "events": [],
            "variable": "sub_current",
            "variableId": f"{DEV_NAME}^~^sub_current",
            "variableSrc": DEV_NAME,
            "ranges": [{"type": "unit", "text": " A"}]
        }
    },
    # Substation Power MW
    "VAL_sub_p": {
        "id": "VAL_sub_p",
        "type": "svg-ext-value",
        "name": "sub_power",
        "label": "Value",
        "property": {
            "events": [],
            "variable": "sub_power",
            "variableId": f"{DEV_NAME}^~^sub_power",
            "variableSrc": DEV_NAME,
            "ranges": [{"type": "unit", "text": " MW"}]
        }
    },
    # Substation Frequency
    "VAL_sub_freq": {
        "id": "VAL_sub_freq",
        "type": "svg-ext-value",
        "name": "sub_freq",
        "label": "Value",
        "property": {
            "events": [],
            "variable": "sub_freq",
            "variableId": f"{DEV_NAME}^~^sub_freq",
            "variableSrc": DEV_NAME,
            "ranges": [{"type": "unit", "text": " Hz"}]
        }
    },
    # Transformer Temp
    "VAL_sub_temp": {
        "id": "VAL_sub_temp",
        "type": "svg-ext-value",
        "name": "sub_trafo_temp",
        "label": "Value",
        "property": {
            "events": [],
            "variable": "sub_trafo_temp",
            "variableId": f"{DEV_NAME}^~^sub_trafo_temp",
            "variableSrc": DEV_NAME,
            "ranges": [{"type": "unit", "text": " °C"}]
        }
    },
    # Breaker Status Semaphore (Red = Live/Closed, Green = Safe/Open)
    "GSE_breaker": {
        "id": "GSE_breaker",
        "type": "svg-ext-gauge_semaphore",
        "name": "sub_breaker_status",
        "label": "HtmlSemaphore",
        "property": {
            "events": [],
            "variable": "sub_breaker_status",
            "variableId": f"{DEV_NAME}^~^sub_breaker_status",
            "variableSrc": DEV_NAME,
            "ranges": [
                {"type": "range", "min": 1, "max": 1, "color": "#ff3838"}, # 1 = Live / Energized (Red in electrical standard)
                {"type": "range", "min": 0, "max": 0, "color": "#2ed573"}  # 0 = Safe / Open (Green in electrical standard)
            ]
        }
    },
    # Button: TRIP Breaker 52-1
    "HXB_trip_breaker": {
        "id": "HXB_trip_breaker",
        "type": "svg-ext-html_button",
        "name": "TRIP",
        "label": "HtmlButton",
        "property": {
            "events": [{"type": "click", "action": "onSetValue", "actparam": "TRIP"}],
            "variable": "sub_breaker_cmd",
            "variableId": f"{DEV_NAME}^~^sub_breaker_cmd",
            "variableSrc": DEV_NAME
        }
    },
    # Button: CLOSE Breaker 52-1
    "HXB_close_breaker": {
        "id": "HXB_close_breaker",
        "type": "svg-ext-html_button",
        "name": "CLOSE",
        "label": "HtmlButton",
        "property": {
            "events": [{"type": "click", "action": "onSetValue", "actparam": "CLOSE"}],
            "variable": "sub_breaker_cmd",
            "variableId": f"{DEV_NAME}^~^sub_breaker_cmd",
            "variableSrc": DEV_NAME
        }
    },

    # Solar Active Generation kW
    "VAL_sol_gen": {
        "id": "VAL_sol_gen",
        "type": "svg-ext-value",
        "name": "sol_generation",
        "label": "Value",
        "property": {
            "events": [],
            "variable": "sol_generation",
            "variableId": f"{DEV_NAME}^~^sol_generation",
            "variableSrc": DEV_NAME,
            "ranges": [{"type": "unit", "text": " kW"}]
        }
    },
    # Solar Irradiance W/m2
    "VAL_sol_irr": {
        "id": "VAL_sol_irr",
        "type": "svg-ext-value",
        "name": "sol_irradiance",
        "label": "Value",
        "property": {
            "events": [],
            "variable": "sol_irradiance",
            "variableId": f"{DEV_NAME}^~^sol_irradiance",
            "variableSrc": DEV_NAME,
            "ranges": [{"type": "unit", "text": " W/m²"}]
        }
    },
    # Solar DC Voltage
    "VAL_sol_dcv": {
        "id": "VAL_sol_dcv",
        "type": "svg-ext-value",
        "name": "sol_dc_voltage",
        "label": "Value",
        "property": {
            "events": [],
            "variable": "sol_dc_voltage",
            "variableId": f"{DEV_NAME}^~^sol_dc_voltage",
            "variableSrc": DEV_NAME,
            "ranges": [{"type": "unit", "text": " V"}]
        }
    },
    # Solar DC Current
    "VAL_sol_dca": {
        "id": "VAL_sol_dca",
        "type": "svg-ext-value",
        "name": "sol_dc_current",
        "label": "Value",
        "property": {
            "events": [],
            "variable": "sol_dc_current",
            "variableId": f"{DEV_NAME}^~^sol_dc_current",
            "variableSrc": DEV_NAME,
            "ranges": [{"type": "unit", "text": " A"}]
        }
    },
    # Solar Inverter Semaphore (Green = Running, Orange = Curtailed)
    "GSE_sol_running": {
        "id": "GSE_sol_running",
        "type": "svg-ext-gauge_semaphore",
        "name": "sol_inv_status",
        "label": "HtmlSemaphore",
        "property": {
            "events": [],
            "variable": "sol_inv_status",
            "variableId": f"{DEV_NAME}^~^sol_inv_status",
            "variableSrc": DEV_NAME,
            "ranges": [
                {"type": "range", "min": 1, "max": 1, "color": "#2ed573"},
                {"type": "range", "min": 0, "max": 0, "color": "#ffa502"}
            ]
        }
    },
    # Button: Enable Solar Inverter
    "HXB_sol_enable": {
        "id": "HXB_sol_enable",
        "type": "svg-ext-html_button",
        "name": "ENABLE",
        "label": "HtmlButton",
        "property": {
            "events": [{"type": "click", "action": "onSetValue", "actparam": "ENABLE"}],
            "variable": "sol_inv_cmd",
            "variableId": f"{DEV_NAME}^~^sol_inv_cmd",
            "variableSrc": DEV_NAME
        }
    },
    # Button: Curtail Solar Inverter
    "HXB_sol_curtail": {
        "id": "HXB_sol_curtail",
        "type": "svg-ext-html_button",
        "name": "CURTAIL",
        "label": "HtmlButton",
        "property": {
            "events": [{"type": "click", "action": "onSetValue", "actparam": "CURTAIL"}],
            "variable": "sol_inv_cmd",
            "variableId": f"{DEV_NAME}^~^sol_inv_cmd",
            "variableSrc": DEV_NAME
        }
    }
}

# 3. High-Fidelity Industrial SVG Graphic
svg_content = """<svg width="1400" height="850" xmlns="http://www.w3.org/2000/svg" xmlns:html="http://www.w3.org/1999/xhtml">
 <defs>
  <linearGradient id="grad_bg" x1="0%" y1="0%" x2="100%" y2="100%">
   <stop offset="0%" stop-color="#0f141c"/>
   <stop offset="100%" stop-color="#1b2431"/>
  </linearGradient>
  <linearGradient id="grad_panel" x1="0%" y1="0%" x2="0%" y2="100%">
   <stop offset="0%" stop-color="#1f2a38"/>
   <stop offset="100%" stop-color="#161e29"/>
  </linearGradient>
  <filter id="glow" x="-20%" y="-20%" width="140%" height="140%">
   <feGaussianBlur stdDeviation="3" result="blur" />
   <feComposite in="SourceGraphic" in2="blur" operator="over" />
  </filter>
 </defs>
 <g>
  <!-- Main Background -->
  <rect width="1400" height="850" fill="url(#grad_bg)"/>

  <!-- Top Banner -->
  <rect x="20" y="15" width="1360" height="60" rx="8" fill="url(#grad_panel)" stroke="#303f52" stroke-width="1.5"/>
  <text x="45" y="52" fill="#00d2d3" font-family="'Segoe UI', Roboto, sans-serif" font-size="22" font-weight="bold" letter-spacing="1">⚡ GUBERNATOR SCADA</text>
  <text x="310" y="52" fill="#f1f2f6" font-family="'Segoe UI', Roboto, sans-serif" font-size="16">| Smart Grid &amp; DNP3 (IEEE 1815) Process Control</text>

  <!-- Status badges -->
  <rect x="880" y="28" width="140" height="34" rx="4" fill="#0c2461" stroke="#1e3799" stroke-width="1"/>
  <text x="950" y="50" text-anchor="middle" fill="#70a1ff" font-family="monospace" font-size="12" font-weight="bold">DNP3 MASTER :1</text>

  <rect x="1035" y="28" width="165" height="34" rx="4" fill="#0c2461" stroke="#1e3799" stroke-width="1"/>
  <text x="1117" y="50" text-anchor="middle" fill="#7bed9f" font-family="monospace" font-size="12" font-weight="bold">SUBSTATION ADDR:10</text>

  <rect x="1215" y="28" width="150" height="34" rx="4" fill="#0c2461" stroke="#1e3799" stroke-width="1"/>
  <text x="1290" y="50" text-anchor="middle" fill="#eccc68" font-family="monospace" font-size="12" font-weight="bold">SOLAR ADDR:20</text>

  <!-- ================= LEFT PANEL: SUBSTATION ALPHA ================= -->
  <rect x="20" y="90" width="670" height="740" rx="10" fill="url(#grad_panel)" stroke="#2c3e50" stroke-width="1.5"/>
  <rect x="20" y="90" width="670" height="45" rx="10" fill="#243342"/>
  <text x="45" y="120" fill="#ff4757" font-family="'Segoe UI', Roboto, sans-serif" font-size="18" font-weight="bold">🏛️ Substation Alpha - 25 kV Distribution (DNP3 RTU 10)</text>

  <!-- Single-Line Diagram Frame -->
  <rect x="40" y="150" width="630" height="350" rx="8" fill="#121820" stroke="#253241" stroke-width="1"/>

  <!-- Busbar 25 kV Transmission Grid -->
  <line x1="70" y1="185" x2="630" y2="185" stroke="#ff4757" stroke-width="6" stroke-linecap="round"/>
  <text x="80" y="175" fill="#ff6b81" font-family="monospace" font-size="13" font-weight="bold">25 kV DISTRIBUTION BUSBAR A</text>

  <!-- Transformer T1 -->
  <line x1="200" y1="185" x2="200" y2="230" stroke="#ffa502" stroke-width="4"/>
  <!-- Disconnector 89-1 -->
  <rect x="190" y="230" width="20" height="30" fill="#2f3542" stroke="#ffa502" stroke-width="2"/>
  <text x="220" y="250" fill="#a4b0be" font-family="monospace" font-size="11">DISC 89-1</text>
  <line x1="200" y1="260" x2="200" y2="290" stroke="#ffa502" stroke-width="4"/>

  <!-- Transformer coils -->
  <circle cx="200" cy="305" r="20" fill="none" stroke="#eccc68" stroke-width="3"/>
  <circle cx="200" cy="335" r="20" fill="none" stroke="#eccc68" stroke-width="3"/>
  <text x="235" y="325" fill="#eccc68" font-family="'Segoe UI', sans-serif" font-size="13" font-weight="bold">TR-1 (25kV/400V)</text>

  <line x1="200" y1="355" x2="200" y2="390" stroke="#00d2d3" stroke-width="4"/>

  <!-- Feeder Circuit Breaker 52-1 Box -->
  <rect x="175" y="390" width="50" height="50" rx="6" fill="#1e272e" stroke="#00d2d3" stroke-width="2.5"/>
  <text x="145" y="460" fill="#ced6e0" font-family="monospace" font-size="13" font-weight="bold">BREAKER 52-1</text>

  <!-- Breaker Semaphore GSE_breaker -->
  <g id="GSE_breaker" type="svg-ext-gauge_semaphore">
   <circle cx="200" cy="415" r="14" fill="#ff3838" stroke="#ffffff" stroke-width="1.5" filter="url(#glow)"/>
  </g>

  <line x1="200" y1="440" x2="200" y2="480" stroke="#00d2d3" stroke-width="4"/>
  <text x="160" y="495" fill="#70a1ff" font-family="monospace" font-size="12">FEEDER 1 TO LOAD</text>

  <!-- Breaker Operator Control Box -->
  <rect x="420" y="220" width="230" height="250" rx="8" fill="#18222d" stroke="#37475a" stroke-width="1.5"/>
  <text x="435" y="248" fill="#f1f2f6" font-family="'Segoe UI', sans-serif" font-size="14" font-weight="bold">🎮 DNP3 CROB Direct Operate</text>
  <text x="435" y="270" fill="#a4b0be" font-family="'Segoe UI', sans-serif" font-size="11">IEEE 1815 Group 12 Var 1</text>

  <!-- CLOSE Breaker Button -->
  <g id="HXB_close_breaker" type="svg-ext-html_button">
   <rect x="440" y="295" width="190" height="42" rx="6" fill="#2ed573" stroke="#26af5f"/>
   <foreignObject x="440" y="295" width="190" height="42">
    <button style="width:100%;height:100%;background:#2ed573;color:#ffffff;font-size:14px;font-weight:bold;border:none;border-radius:6px;cursor:pointer;">⚡ CLOSE 52-1 (ENERGIZAR)</button>
   </foreignObject>
  </g>

  <!-- TRIP Breaker Button -->
  <g id="HXB_trip_breaker" type="svg-ext-html_button">
   <rect x="440" y="355" width="190" height="42" rx="6" fill="#ff4757" stroke="#d63031"/>
   <foreignObject x="440" y="355" width="190" height="42">
    <button style="width:100%;height:100%;background:#ff4757;color:#ffffff;font-size:14px;font-weight:bold;border:none;border-radius:6px;cursor:pointer;">🛑 TRIP 52-1 (DISPARAR)</button>
   </foreignObject>
  </g>
  <text x="440" y="425" fill="#eccc68" font-family="monospace" font-size="10">Real-time CROB latch via TCP:20000</text>

  <!-- Substation Telemetry Instruments Grid -->
  <text x="45" y="530" fill="#dfe4ea" font-family="'Segoe UI', sans-serif" font-size="15" font-weight="bold">📊 Substation Telemetry (Analog Inputs Group 30)</text>

  <!-- Tile: Voltage -->
  <rect x="40" y="545" width="195" height="80" rx="8" fill="#131c26" stroke="#253545" stroke-width="1"/>
  <text x="55" y="572" fill="#747d8c" font-family="'Segoe UI', sans-serif" font-size="12" font-weight="bold">BUSBAR VOLTAGE</text>
  <g id="VAL_sub_v" type="svg-ext-value">
   <text x="55" y="610" fill="#00d2d3" font-family="monospace" font-size="24" font-weight="bold">25.0 kV</text>
  </g>

  <!-- Tile: Current -->
  <rect x="255" y="545" width="195" height="80" rx="8" fill="#131c26" stroke="#253545" stroke-width="1"/>
  <text x="270" y="572" fill="#747d8c" font-family="'Segoe UI', sans-serif" font-size="12" font-weight="bold">FEEDER CURRENT</text>
  <g id="VAL_sub_i" type="svg-ext-value">
   <text x="270" y="610" fill="#ffa502" font-family="monospace" font-size="24" font-weight="bold">150.0 A</text>
  </g>

  <!-- Tile: Active Power -->
  <rect x="470" y="545" width="195" height="80" rx="8" fill="#131c26" stroke="#253545" stroke-width="1"/>
  <text x="485" y="572" fill="#747d8c" font-family="'Segoe UI', sans-serif" font-size="12" font-weight="bold">ACTIVE POWER</text>
  <g id="VAL_sub_p" type="svg-ext-value">
   <text x="485" y="610" fill="#ff4757" font-family="monospace" font-size="24" font-weight="bold">5.20 MW</text>
  </g>

  <!-- Tile: Frequency -->
  <rect x="40" y="640" width="195" height="80" rx="8" fill="#131c26" stroke="#253545" stroke-width="1"/>
  <text x="55" y="667" fill="#747d8c" font-family="'Segoe UI', sans-serif" font-size="12" font-weight="bold">GRID FREQUENCY</text>
  <g id="VAL_sub_freq" type="svg-ext-value">
   <text x="55" y="705" fill="#2ed573" font-family="monospace" font-size="24" font-weight="bold">50.00 Hz</text>
  </g>

  <!-- Tile: Transformer Temp -->
  <rect x="255" y="640" width="195" height="80" rx="8" fill="#131c26" stroke="#253545" stroke-width="1"/>
  <text x="270" y="667" fill="#747d8c" font-family="'Segoe UI', sans-serif" font-size="12" font-weight="bold">TRANSFORMER TEMP</text>
  <g id="VAL_sub_temp" type="svg-ext-value">
   <text x="270" y="705" fill="#eccc68" font-family="monospace" font-size="24" font-weight="bold">62.5 °C</text>
  </g>

  <!-- Tile: SF6 Pressure & Relay Status -->
  <rect x="470" y="640" width="195" height="80" rx="8" fill="#131c26" stroke="#253545" stroke-width="1"/>
  <text x="485" y="667" fill="#747d8c" font-family="'Segoe UI', sans-serif" font-size="12" font-weight="bold">PROTECTIONS</text>
  <text x="485" y="695" fill="#2ed573" font-family="monospace" font-size="14" font-weight="bold">● SF6 GAS NORMAL</text>
  <text x="485" y="714" fill="#a4b0be" font-family="monospace" font-size="12">● RELAY 50/51 OK</text>


  <!-- ================= RIGHT PANEL: SOLAR PV FARM ================= -->
  <rect x="710" y="90" width="670" height="740" rx="10" fill="url(#grad_panel)" stroke="#2c3e50" stroke-width="1.5"/>
  <rect x="710" y="90" width="670" height="45" rx="10" fill="#243342"/>
  <text x="735" y="120" fill="#eccc68" font-family="'Segoe UI', Roboto, sans-serif" font-size="18" font-weight="bold">☀️ Solar PV Farm Beta - 3 MW Inverter Field (DNP3 RTU 20)</text>

  <!-- Solar Field Synoptic Frame -->
  <rect x="730" y="150" width="630" height="350" rx="8" fill="#121820" stroke="#253241" stroke-width="1"/>

  <!-- Solar Panel Array Graphic -->
  <g transform="translate(760, 190)">
   <!-- PV Panel 1 -->
   <rect x="0" y="0" width="70" height="50" rx="4" fill="#0c2461" stroke="#4a69bd" stroke-width="2"/>
   <line x1="23" y1="0" x2="23" y2="50" stroke="#4a69bd" stroke-width="1"/>
   <line x1="46" y1="0" x2="46" y2="50" stroke="#4a69bd" stroke-width="1"/>
   <line x1="0" y1="25" x2="70" y2="25" stroke="#4a69bd" stroke-width="1"/>
   <!-- PV Panel 2 -->
   <rect x="85" y="0" width="70" height="50" rx="4" fill="#0c2461" stroke="#4a69bd" stroke-width="2"/>
   <line x1="108" y1="0" x2="108" y2="50" stroke="#4a69bd" stroke-width="1"/>
   <line x1="131" y1="0" x2="131" y2="50" stroke="#4a69bd" stroke-width="1"/>
   <line x1="85" y1="25" x2="155" y2="25" stroke="#4a69bd" stroke-width="1"/>
   <!-- PV Panel 3 -->
   <rect x="170" y="0" width="70" height="50" rx="4" fill="#0c2461" stroke="#4a69bd" stroke-width="2"/>
   <line x1="193" y1="0" x2="193" y2="50" stroke="#4a69bd" stroke-width="1"/>
   <line x1="216" y1="0" x2="216" y2="50" stroke="#4a69bd" stroke-width="1"/>
   <line x1="170" y1="25" x2="240" y2="25" stroke="#4a69bd" stroke-width="1"/>
  </g>

  <!-- Sun Graphic -->
  <circle cx="1070" cy="205" r="24" fill="#ffa502" filter="url(#glow)"/>
  <text x="1070" y="245" text-anchor="middle" fill="#eccc68" font-family="'Segoe UI', sans-serif" font-size="12" font-weight="bold">IRRADIANCE</text>

  <!-- DC Bus to Central Inverter -->
  <line x1="880" y1="240" x2="880" y2="300" stroke="#eccc68" stroke-width="4"/>
  <rect x="830" y="300" width="100" height="70" rx="8" fill="#1e272e" stroke="#ffa502" stroke-width="2.5"/>
  <text x="880" y="332" text-anchor="middle" fill="#f1f2f6" font-family="'Segoe UI', sans-serif" font-size="12" font-weight="bold">INVERTER</text>
  <text x="880" y="350" text-anchor="middle" fill="#eccc68" font-family="monospace" font-size="10">DC ➔ AC</text>

  <!-- Inverter Semaphore GSE_sol_running -->
  <g id="GSE_sol_running" type="svg-ext-gauge_semaphore">
   <circle cx="880" cy="395" r="14" fill="#2ed573" stroke="#ffffff" stroke-width="1.5" filter="url(#glow)"/>
  </g>
  <text x="880" y="425" text-anchor="middle" fill="#2ed573" font-family="monospace" font-size="12" font-weight="bold">STATUS: RUNNING</text>

  <!-- AC Connection to Grid -->
  <line x1="880" y1="440" x2="880" y2="480" stroke="#2ed573" stroke-width="4"/>
  <text x="880" y="495" text-anchor="middle" fill="#00d2d3" font-family="monospace" font-size="12">AC EXPORT TO GRID</text>

  <!-- Solar Curtailment Control Box -->
  <rect x="1110" y="255" width="230" height="215" rx="8" fill="#18222d" stroke="#37475a" stroke-width="1.5"/>
  <text x="1125" y="280" fill="#f1f2f6" font-family="'Segoe UI', sans-serif" font-size="14" font-weight="bold">⚡ DNP3 Inverter Curtailment</text>
  <text x="1125" y="300" fill="#a4b0be" font-family="'Segoe UI', sans-serif" font-size="11">Direct Operate BO 0</text>

  <!-- Enable Button -->
  <g id="HXB_sol_enable" type="svg-ext-html_button">
   <rect x="1130" y="320" width="190" height="42" rx="6" fill="#2ed573" stroke="#26af5f"/>
   <foreignObject x="1130" y="320" width="190" height="42">
    <button style="width:100%;height:100%;background:#2ed573;color:#ffffff;font-size:14px;font-weight:bold;border:none;border-radius:6px;cursor:pointer;">☀️ ENABLE INVERTER</button>
   </foreignObject>
  </g>

  <!-- Curtail Button -->
  <g id="HXB_sol_curtail" type="svg-ext-html_button">
   <rect x="1130" y="380" width="190" height="42" rx="6" fill="#ffa502" stroke="#e67e22"/>
   <foreignObject x="1130" y="380" width="190" height="42">
    <button style="width:100%;height:100%;background:#ffa502;color:#ffffff;font-size:14px;font-weight:bold;border:none;border-radius:6px;cursor:pointer;">⚠️ CURTAIL / STOP</button>
   </foreignObject>
  </g>

  <!-- Solar Measurements Grid -->
  <text x="735" y="530" fill="#dfe4ea" font-family="'Segoe UI', sans-serif" font-size="15" font-weight="bold">📊 Photovoltaic Telemetry (Analog Inputs Group 30)</text>

  <!-- Tile: Generation kW -->
  <rect x="730" y="545" width="195" height="80" rx="8" fill="#131c26" stroke="#253545" stroke-width="1"/>
  <text x="745" y="572" fill="#747d8c" font-family="'Segoe UI', sans-serif" font-size="12" font-weight="bold">ACTIVE GENERATION</text>
  <g id="VAL_sol_gen" type="svg-ext-value">
   <text x="745" y="610" fill="#2ed573" font-family="monospace" font-size="24" font-weight="bold">2450 kW</text>
  </g>

  <!-- Tile: Irradiance W/m2 -->
  <rect x="945" y="545" width="195" height="80" rx="8" fill="#131c26" stroke="#253545" stroke-width="1"/>
  <text x="960" y="572" fill="#747d8c" font-family="'Segoe UI', sans-serif" font-size="12" font-weight="bold">SOLAR IRRADIANCE</text>
  <g id="VAL_sol_irr" type="svg-ext-value">
   <text x="960" y="610" fill="#ffa502" font-family="monospace" font-size="24" font-weight="bold">820 W/m²</text>
  </g>

  <!-- Tile: DC Voltage -->
  <rect x="1160" y="545" width="195" height="80" rx="8" fill="#131c26" stroke="#253545" stroke-width="1"/>
  <text x="1175" y="572" fill="#747d8c" font-family="'Segoe UI', sans-serif" font-size="12" font-weight="bold">DC STRING VOLTAGE</text>
  <g id="VAL_sol_dcv" type="svg-ext-value">
   <text x="1175" y="610" fill="#00d2d3" font-family="monospace" font-size="24" font-weight="bold">750.0 V</text>
  </g>

  <!-- Tile: DC Current -->
  <rect x="730" y="640" width="195" height="80" rx="8" fill="#131c26" stroke="#253545" stroke-width="1"/>
  <text x="745" y="667" fill="#747d8c" font-family="'Segoe UI', sans-serif" font-size="12" font-weight="bold">DC ARRAY CURRENT</text>
  <g id="VAL_sol_dca" type="svg-ext-value">
   <text x="745" y="705" fill="#ffa502" font-family="monospace" font-size="24" font-weight="bold">3260 A</text>
  </g>

  <!-- Tile: Inverter Temp -->
  <rect x="945" y="640" width="195" height="80" rx="8" fill="#131c26" stroke="#253545" stroke-width="1"/>
  <text x="960" y="667" fill="#747d8c" font-family="'Segoe UI', sans-serif" font-size="12" font-weight="bold">INVERTER TEMP</text>
  <text x="960" y="705" fill="#eccc68" font-family="monospace" font-size="24" font-weight="bold">48.2 °C</text>

  <!-- Tile: Anti-islanding & Sync -->
  <rect x="1160" y="640" width="195" height="80" rx="8" fill="#131c26" stroke="#253545" stroke-width="1"/>
  <text x="1175" y="667" fill="#747d8c" font-family="'Segoe UI', sans-serif" font-size="12" font-weight="bold">GRID SYNC / ISLAND</text>
  <text x="1175" y="695" fill="#2ed573" font-family="monospace" font-size="14" font-weight="bold">● ANTI-ISLAND OK</text>
  <text x="1175" y="714" fill="#2ed573" font-family="monospace" font-size="12">● 50 Hz SYNC LOCKED</text>

  <!-- Footer Info Bar -->
  <rect x="40" y="740" width="1315" height="70" rx="8" fill="#141c26" stroke="#2c3e50" stroke-width="1"/>
  <text x="60" y="768" fill="#70a1ff" font-family="monospace" font-size="13" font-weight="bold">PROTOCOL TELEMETRY BUS:</text>
  <text x="270" y="768" fill="#a4b0be" font-family="monospace" font-size="12">IEEE 1815-2012 (DNP3) ➔ Cyclic Integrity Poll Class 0/1/2/3 ➔ Mosquitto MQTT Bridge ➔ FUXA SVG Engine</text>
  <text x="60" y="792" fill="#2ed573" font-family="monospace" font-size="12">CROB FEEDBACK LOOP:</text>
  <text x="270" y="792" fill="#ced6e0" font-family="monospace" font-size="12">FUXA UI click ➔ MQTT topic 'scada/dnp3/control/...' ➔ DNP3 Master Station ➔ TCP Direct Operate ➔ RTU Breaker Action</text>
 </g>
</svg>"""

view_main = {
    "id": "v_main_scada",
    "name": "Electrical Substation & Solar SCADA (DNP3)",
    "profile": {
        "width": 1400,
        "height": 850,
        "bkcolor": "#0f141c"
    },
    "items": items,
    "variables": {},
    "svgcontent": svg_content
}

project = {
    "version": "1.00",
    "server": {
        "id": "0",
        "name": "FUXA Server",
        "type": "FuxaServer",
        "property": {}
    },
    "devices": {
        DEV_ID: device
    },
    "hmi": {
        "views": [view_main],
        "layout": {
            "start": "v_main_scada",
            "navigation": {
                "mode": "top",
                "items": []
            }
        }
    },
    "charts": {},
    "alarms": {}
}

# 4. Save project.fuxap JSON file
json_path = os.path.join(TARGET_DIR, "project.fuxap")
with open(json_path, "w", encoding="utf-8") as f:
    json.dump(project, f, indent=2, ensure_ascii=False)
print(f"✅ Generated JSON project file: {json_path}")

# 5. Build SQLite project.fuxap.db database
db_path = os.path.join(TARGET_DIR, "project.fuxap.db")
if os.path.exists(db_path):
    os.remove(db_path)

conn = sqlite3.connect(db_path)
cur = conn.cursor()

# Create standard FUXA tables
cur.executescript("""
CREATE TABLE if not exists general (name TEXT PRIMARY KEY, value TEXT);
CREATE TABLE if not exists views (name TEXT PRIMARY KEY, value TEXT);
CREATE TABLE if not exists devices (name TEXT PRIMARY KEY, value TEXT, connection TEXT, cntid TEXT, cntpwd TEXT);
CREATE TABLE if not exists devicesSecurity (name TEXT PRIMARY KEY, value TEXT);
CREATE TABLE if not exists texts (name TEXT PRIMARY KEY, value TEXT);
CREATE TABLE if not exists alarms (name TEXT PRIMARY KEY, value TEXT);
CREATE TABLE if not exists notifications (name TEXT PRIMARY KEY, value TEXT);
CREATE TABLE if not exists scripts (name TEXT PRIMARY KEY, value TEXT);
CREATE TABLE if not exists reports (name TEXT PRIMARY KEY, value TEXT);
CREATE TABLE if not exists locations (name TEXT PRIMARY KEY, value TEXT);
CREATE TABLE if not exists arMarkers (name TEXT PRIMARY KEY, value TEXT);
""")

# Insert project data into tables
cur.execute("INSERT INTO general (name, value) VALUES (?, ?)", ("version", json.dumps("1.00")))
cur.execute("INSERT INTO general (name, value) VALUES (?, ?)", ("layout", json.dumps(project["hmi"]["layout"])))
cur.execute("INSERT INTO general (name, value) VALUES (?, ?)", ("charts", json.dumps({})))

# Insert devices
cur.execute("INSERT INTO general (name, value) VALUES (?, ?)", ("server", json.dumps(project["server"])))
cur.execute("INSERT INTO devices (name, value) VALUES (?, ?)", (DEV_ID, json.dumps(device)))

# Insert views
cur.execute("INSERT INTO views (name, value) VALUES (?, ?)", ("v_main_scada", json.dumps(view_main)))

conn.commit()
conn.close()
print(f"✅ Generated SQLite project database: {db_path}")
print("🎉 FUXA pre-configured project generation completed successfully!")
