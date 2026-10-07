# Prebakes kfp so air-gapped UI tutorials never hit PyPI (NCN-118204).
FROM python:3.9-slim

RUN pip install --no-cache-dir kfp==2.14.3 \
    && useradd --create-home --uid 1000 --shell /usr/sbin/nologin kfp

USER 1000:1000
WORKDIR /home/kfp
