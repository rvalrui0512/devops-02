# start by pulling the python image
FROM python:3-slim

# switch working directory
WORKDIR /app

# copy the requirements file into the image
COPY ./requirements.txt ./

# install the dependencies and packages in the requirements file
RUN pip install -r requirements.txt

# copy every content from the local file to the image
COPY src .

# configure the container to run in an executed manner
# CMD gunicorn --bind 0.0.0.0:5000 app:app
CMD ["gunicorn",  "--bind",  "0.0.0.0:5000", "app:app"]