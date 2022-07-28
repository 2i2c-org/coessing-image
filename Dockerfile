FROM pangeo/pangeo-notebook:2022.07.13

USER root
ENV DEBIAN_FRONTEND=noninteractive
ENV PATH ${NB_PYTHON_PREFIX}/bin:$PATH

# Needed for apt-key to work
RUN apt-get update -qq --yes > /dev/null && \
    apt-get install --yes -qq gnupg2 > /dev/null

ENV JULIA_VERSION 1.7.3
ENV JULIA_PATH /srv/julia
ENV JULIA_DEPOT_PATH ${JULIA_PATH}/pkg
ENV PATH $PATH:${JULIA_PATH}/bin
RUN mkdir -p ${JULIA_PATH} \
 && curl -sSL "https://julialang-s3.julialang.org/bin/linux/x64/${JULIA_VERSION%[.-]*}/julia-${JULIA_VERSION}-linux-x86_64.tar.gz" \
  | tar -xz -C ${JULIA_PATH} --strip-components 1 \
 && mkdir -p ${JULIA_DEPOT_PATH} \
 && chown ${NB_UID}:${NB_UID} ${JULIA_DEPOT_PATH}

USER ${NB_USER}

COPY environment.yml /tmp/

RUN mamba env update --name ${CONDA_ENV} -f /tmp/environment.yml

# Remove nb_conda_kernels from the env for now
RUN mamba remove -n ${CONDA_ENV} nb_conda_kernels

COPY install-jupyter-extensions.bash /tmp/install-jupyter-extensions.bash
RUN /tmp/install-jupyter-extensions.bash

RUN export JUPYTER_DATA_DIR="$NB_PYTHON_PREFIX/share/jupyter" \
 && julia --eval 'using Pkg; Pkg.add("IJulia"); using IJulia; installkernel("Julia");' \
 && julia --eval 'using Pkg; Pkg.add(["Oceananigans", "CairoMakie", "Downloads", "JLD2", "KernelAbstractions"]);' \
 && julia --eval 'using Pkg; Pkg.instantiate(); Pkg.resolve(); pkg"precompile"'

# Set bash as shell in terminado.
ADD jupyter_notebook_config.py  ${NB_PYTHON_PREFIX}/etc/jupyter/
# Disable history.
ADD ipython_config.py ${NB_PYTHON_PREFIX}/etc/ipython/
