FROM python:3.11-slim

WORKDIR /app

ENV PYTHONUNBUFFERED=1

COPY requirements.txt /app/requirements.txt
RUN pip install --no-cache-dir -r /app/requirements.txt

COPY dnp3_frame.py /app/dnp3_frame.py
COPY outstation_substation.py /app/outstation_substation.py
COPY outstation_solar.py /app/outstation_solar.py
COPY master_bridge.py /app/master_bridge.py

EXPOSE 20000

CMD ["python3", "outstation_substation.py"]
