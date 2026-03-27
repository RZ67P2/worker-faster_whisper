# Blackwell (RTX 5090) requires CUDA >= 12.8 and cuDNN 9
# RunPod serverless RTX 5090 hosts run driver 570.x (native CUDA 12.9 support)
# CUDA 12.8.1 runs natively on driver 570+ — no forward compat needed
FROM nvidia/cuda:12.8.1-cudnn-runtime-ubuntu22.04

# Remove any third-party apt sources to avoid issues with expiring keys.
RUN rm -f /etc/apt/sources.list.d/*.list

# Set shell and noninteractive environment variables
SHELL ["/bin/bash", "-c"]
ENV DEBIAN_FRONTEND=noninteractive
ENV SHELL=/bin/bash

# Set working directory
WORKDIR /

# Update and upgrade the system packages
RUN apt-get update -y && \
    apt-get upgrade -y && \
    apt-get install --yes --no-install-recommends sudo ca-certificates git wget curl bash libgl1 libx11-6 software-properties-common ffmpeg build-essential -y &&\
    apt-get autoremove -y && \
    apt-get clean -y && \
    rm -rf /var/lib/apt/lists/*

# Install Python 3.11 via deadsnakes PPA (not available natively on Ubuntu 22.04)
RUN add-apt-repository ppa:deadsnakes/ppa && \
    apt-get update -y && \
    apt-get install python3.11 python3.11-dev python3.11-venv python3-pip -y --no-install-recommends && \
    ln -s /usr/bin/python3.11 /usr/bin/python && \
    rm -f /usr/bin/python3 && \
    ln -s /usr/bin/python3.11 /usr/bin/python3 && \
    apt-get autoremove -y && \
    apt-get clean -y && \
    rm -rf /var/lib/apt/lists/*

# Install Python dependencies
COPY builder/requirements.txt /requirements.txt
RUN --mount=type=cache,target=/root/.cache/pip \
    pip install --upgrade pip && \
    pip install huggingface_hub[hf_xet] && \
    pip install -r /requirements.txt --no-cache-dir

# Copy and run script to fetch models
COPY builder/fetch_models.py /fetch_models.py
RUN python /fetch_models.py && \
    rm /fetch_models.py

# Copy handler and other code
COPY src .

# test input that will be used when the container runs outside of runpod
COPY test_input.json .

# Set default command
CMD python -u /rp_handler.py
