FROM pangeo/pangeo-notebook:6b2df38

USER root
ENV DEBIAN_FRONTEND=noninteractive
ENV R_LIBS_USER /opt/r
ENV PATH ${NB_PYTHON_PREFIX}/bin:$PATH

# Create user owned R libs dir
# This lets users temporarily install packages
RUN mkdir -p ${R_LIBS_USER} && chown ${NB_USER}:${NB_USER} ${R_LIBS_USER}

# Needed for apt-key to work
RUN apt-get update -qq --yes > /dev/null && \
    apt-get install --yes -qq gnupg2 > /dev/null

# Install R packages
# Our pre-built R packages from rspm are built against system libs in focal
# rstan takes forever to compile from source, and needs libnodejs
# So we install older (10.x) nodejs from apt rather than newer from conda
# We don't want R 4.1 yet, so we pin to R 4.0.5
ENV R_VERSION=4.0.5-1.2004.0
RUN apt-key adv --keyserver keyserver.ubuntu.com --recv-keys E298A3A825C0D65DFD57CBB651716619E084DAB9
RUN echo "deb https://cloud.r-project.org/bin/linux/ubuntu focal-cran40/" > /etc/apt/sources.list.d/cran.list
# Packages we want are installed with R, so we use apt to *just* get R
RUN apt-get update -qq --yes > /dev/null && \
    apt-get install --yes \
    r-base-core=${R_VERSION} \
    r-base-dev=${R_VERSION} \
    r-cran-littler > /dev/null

# Needed by many R libraries
# Picked up from https://github.com/rocker-org/rocker/blob/9dc3e458d4e92a8f41ccd75687cd7e316e657cc0/r-rspm/focal/Dockerfile
# Our pre-built R packages from rspm are built against system libs in focal
# Some were required for lwgeom https://packagemanager.rstudio.com/client/#/repos/1/packages/lwgeom
# libzmq3 is needed by IRKernel
RUN apt-get update > /dev/null && \
    apt-get install -y --no-install-recommends \
        libgdal26 \
        libgeos-3.8.0 \
        libudunits2-0 \
        libxml2 \
        libzmq5 \
        libglu1-mesa-dev \
        libgl1-mesa-dev \
        libudunits2-dev \
        libgdal-dev \
        gdal-bin \
        libgeos-dev \
        libproj-dev \
        libglpk-dev \
        libgmp3-dev \
        libssl-dev \
        libxml2-dev > /dev/null

# Needed by RStudio
RUN apt-get update -qq --yes && \
    apt-get install --yes --no-install-recommends -qq \
        psmisc \
        sudo \
        libapparmor1 \
        lsb-release \
        libclang-dev  > /dev/null

# Download and install rstudio manually
# Newer one has bug that doesn't work with jupyter-rsession-proxy
ENV RSTUDIO_URL https://download2.rstudio.org/server/bionic/amd64/rstudio-server-1.3.959-amd64.deb
RUN curl --silent --location --fail ${RSTUDIO_URL} > /tmp/rstudio.deb && \
    dpkg -i /tmp/rstudio.deb && \
    rm /tmp/rstudio.deb
#
# R_LIBS_USER is set by default in /etc/R/Renviron, which RStudio loads.
# We uncomment the default, and set what we wanna - so it picks up
# the packages we install. Without this, RStudio doesn't see the packages
# that R does.
# Stolen from https://github.com/jupyterhub/repo2docker/blob/6a07a48b2df48168685bb0f993d2a12bd86e23bf/repo2docker/buildpacks/r.py
RUN sed -i -e '/^R_LIBS_USER=/s/^/#/' /etc/R/Renviron && \
    echo "R_LIBS_USER=${R_LIBS_USER}" >> /etc/R/Renviron

# Set CRAN mirror to rspm before we install anything
COPY Rprofile.site /usr/lib/R/etc/Rprofile.site
# RStudio needs its own config
COPY rsession.conf /etc/rstudio/rsession.conf

USER ${NB_USER}

COPY environment.yml /tmp/

RUN conda env update --name ${CONDA_ENV} -f /tmp/environment.yml

# Remove nb_conda_kernels from the env for now
RUN conda remove -n ${CONDA_ENV} nb_conda_kernels

COPY install-jupyter-extensions.bash /tmp/install-jupyter-extensions.bash
RUN /tmp/install-jupyter-extensions.bash

# Install IRKernel
RUN r -e "install.packages('IRkernel', version='1.1.1')" && \
    r -e "IRkernel::installspec(prefix='${NB_PYTHON_PREFIX}')"

# Install R packages, cleanup temp package download location
COPY install.R /tmp/install.R
RUN /tmp/install.R && \
 	rm -rf /tmp/downloaded_packages/ /tmp/*.rds

COPY install-github.R /tmp/install-github.R
RUN /tmp/install-github.R && \
 	rm -rf /tmp/downloaded_packages/ /tmp/*.rds


# Set bash as shell in terminado.
ADD jupyter_notebook_config.py  ${NB_PYTHON_PREFIX}/etc/jupyter/
# Disable history.
ADD ipython_config.py ${NB_PYTHON_PREFIX}/etc/ipython/
