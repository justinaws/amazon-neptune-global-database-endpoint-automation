#!/bin/bash

EXPLORER_VERSION=""
for i in "$@"
do
case $i in
    -ev=*|--explorer-version=*)
    EXPLORER_VERSION="${i#*=}"
    echo "set explorer version to ${EXPLORER_VERSION}"
    shift
    ;;
esac
done

VERSION=""
for i in "$@"
do
case $i in
    -v=*|--version=*)
    VERSION="${i#*=}"
    echo "set notebook version to ${VERSION}"
    shift
    ;;
esac
done

source activate JupyterSystemEnv

echo "installing Python 3 kernel"
python3 -m ipykernel install --sys-prefix --name python3 --display-name "Python 3"

echo "intalling python dependencies..."
pip uninstall NeptuneGraphNotebook -y # legacy uninstall when we used to install from source in s3

pip install "jupyter-console<=6.4.0"
pip install "jupyter-client<=6.1.12"
pip install "ipywidgets==7.7.2"
pip install "jupyterlab_widgets==1.1.1"
pip install "notebook==6.4.12"
pip install "nbclient<=0.7.0"
pip install "itables<=1.4.2"
pip install awswrangler

if [[ ${VERSION} == "" ]]; then
  pip install --upgrade graph-notebook
else
  pip install --upgrade graph-notebook==${VERSION}
fi

echo "installing nbextensions..."
python -m graph_notebook.nbextensions.install

echo "installing static resources..."
python -m graph_notebook.static_resources.install

echo "enabling visualization..."
if [[ ${VERSION//./} < 330 ]] && [[ ${VERSION} != "" ]]; then
  jupyter nbextension install --py --sys-prefix graph_notebook.widgets
fi
jupyter nbextension enable  --py --sys-prefix graph_notebook.widgets

mkdir -p ~/SageMaker/Neptune
cd ~/SageMaker/Neptune || exit
python -m graph_notebook.notebooks.install
chmod -R a+rw ~/SageMaker/Neptune/*

source ~/.bashrc || exit
HOST=${GRAPH_NOTEBOOK_HOST}
PORT=${GRAPH_NOTEBOOK_PORT}
AUTH_MODE=${GRAPH_NOTEBOOK_AUTH_MODE}
SSL=${GRAPH_NOTEBOOK_SSL}
LOAD_FROM_S3_ARN=${NEPTUNE_LOAD_FROM_S3_ROLE_ARN}

if [[ ${SSL} -eq "" ]]; then
  SSL="True"
fi

echo "Creating config with
HOST:                       ${HOST}
PORT:                       ${PORT}
AUTH_MODE:                  ${AUTH_MODE}
SSL:                        ${SSL}
AWS_REGION:                 ${AWS_REGION}"

/home/ec2-user/anaconda3/envs/JupyterSystemEnv/bin/python -m graph_notebook.configuration.generate_config \
  --host "${HOST}" \
  --port "${PORT}" \
  --auth_mode "${AUTH_MODE}" \
  --ssl "${SSL}" \
  --load_from_s3_arn "${LOAD_FROM_S3_ARN}" \
  --aws_region "${AWS_REGION}"

echo "Adding graph_notebook.magics to ipython config..."
if [[ ${VERSION//./} > 341 ]] || [[ ${VERSION} == "" ]]; then
  /home/ec2-user/anaconda3/envs/JupyterSystemEnv/bin/python -m graph_notebook.ipython_profile.configure_ipython_profile
else
  echo "Skipping, unsupported on graph-notebook<=3.4.1"
fi

echo "graph-notebook installation complete."

echo "Constructing explorer connection configuration..."

GRAPH_NOTEBOOK_NAME=$(jq '.ResourceName' /opt/ml/metadata/resource-metadata.json --raw-output)
echo "Grabbed notebook name: ${GRAPH_NOTEBOOK_NAME}"

EXPLORER_URI="https://${GRAPH_NOTEBOOK_NAME}.notebook.${AWS_REGION}.sagemaker.aws/proxy/9250"
NEPTUNE_URI="https://${GRAPH_NOTEBOOK_HOST}:${GRAPH_NOTEBOOK_PORT}"
AWS_REGION=${AWS_REGION}
echo "AUTH_MODE from Lifecycle: ${GRAPH_NOTEBOOK_AUTH_MODE}"
if [[ ${GRAPH_NOTEBOOK_AUTH_MODE} == "IAM" ]]; then
  IAM=true
else
  IAM=false
fi

echo "Explorer URI: ${EXPLORER_URI}"
echo "Neptune URI: ${NEPTUNE_URI}"
echo "Explorer region: ${AWS_REGION}"
echo "Explorer IAM auth mode: ${IAM}"

echo "Pulling and starting graph-explorer..."
if [[ ${EXPLORER_VERSION} == "" ]]; then
  EXPLORER_ECR_TAG=sagemaker-latest
else
  EXPLORER_ECR_TAG=sagemaker-${EXPLORER_VERSION}
fi
echo "Using explorer image tag: ${EXPLORER_ECR_TAG}"

docker run -d -p 9250:9250 \
  --env HOST=127.0.0.1 \
  --env PUBLIC_OR_PROXY_ENDPOINT=${EXPLORER_URI} \
  --env GRAPH_CONNECTION_URL=${NEPTUNE_URI} \
  --env USING_PROXY_SERVER=true \
  --env IAM=${IAM} \
  --env AWS_REGION=${AWS_REGION} \
  --env PROXY_SERVER_HTTPS_CONNECTION=false \
  --env NEPTUNE_NOTEBOOK=true public.ecr.aws/neptune/graph-explorer:${EXPLORER_ECR_TAG}

echo "Explorer installation done."

conda /home/ec2-user/anaconda3/bin/deactivate
echo "done."