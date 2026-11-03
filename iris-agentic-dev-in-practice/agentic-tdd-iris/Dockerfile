ARG IMAGE=intersystems/iris-community:latest-cd
FROM $IMAGE

# Same one-time setup pattern as the intersystems-iris-dev-template, baked into
# the image during the build: the fresh-container account fix (SuperUser must
# change password + is locked out until then), the REST web application, the
# inherited seed app (the rooms package), and the test-root directory that
# %UnitTest.Manager expects to exist at runtime.
COPY src/*.cls /tmp/seed/
COPY iris.script /home/irisowner/iris.script
RUN mkdir -p /home/irisowner/dev/tests/rooms/Tests
RUN iris start IRIS && \
    iris session IRIS < /home/irisowner/iris.script && \
    iris stop IRIS quietly
