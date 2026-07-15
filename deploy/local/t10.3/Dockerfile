ARG ORACLE_IMAGE=gvenzl/oracle-free:23.26.2-full
FROM ${ORACLE_IMAGE} AS oracle_client

ARG PLAYWRIGHT_IMAGE=mcr.microsoft.com/playwright:v1.61.0-noble
FROM ${PLAYWRIGHT_IMAGE}

USER root
ENV ORACLE_HOME=/opt/oracle/product/23ai/dbhomeFree \
    LD_LIBRARY_PATH=/opt/oracle/product/23ai/dbhomeFree/lib \
    PATH=/opt/oracle/product/23ai/dbhomeFree/bin:${PATH} \
    PLAYWRIGHT_BROWSERS_PATH=/ms-playwright \
    HOME=/tmp/home
COPY --from=oracle_client /opt/oracle/product/23ai/dbhomeFree /opt/oracle/product/23ai/dbhomeFree
WORKDIR /workspace
COPY package.json package-lock.json ./
RUN npm ci --ignore-scripts --no-audit --no-fund \
 && npm cache clean --force
COPY --chown=1000:1000 . /workspace
COPY --chown=1000:1000 deploy/local/t10.3/db_sql.sh /workspace/scripts/db_sql.sh
RUN chmod 0555 /workspace/scripts/db_sql.sh /workspace/verify.sh \
 && mkdir -p /tmp/home \
 && chown 1000:1000 /tmp/home
USER 1000:1000
ENTRYPOINT ["node"]
CMD ["evaluator/t10.3/run-container.mjs"]
