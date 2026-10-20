FROM public.ecr.aws/lambda/python:3.14

RUN dnf update -y && \
    dnf clean all

RUN pip install --no-cache-dir --upgrade \
    setuptools \
    msgpack \
    urllib3

COPY requirements.txt ${LAMBDA_TASK_ROOT}/

RUN pip install --no-cache-dir -r requirements.txt --target ${LAMBDA_TASK_ROOT}

COPY app ${LAMBDA_TASK_ROOT}/app

CMD ["app.main.handler"]