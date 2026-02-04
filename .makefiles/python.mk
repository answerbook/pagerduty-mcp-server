lint:: lint-python
setup:: setup-python
test:: test-pytest
version:: version-python

PYTHON_VERSION ?= latest
PYTHON_IMAGE ?= us.gcr.io/logdna-k8s/tooling-python
SEMANTIC_RELEASE_CONFIG ?= pyproject.toml
JENKINS_URL_FILE ?= $(TMP_DIR)/.jenkins

REPORTSDIR ?= ./reports

ifeq ("$(PYTHON_VERSION)", "")
$(error PYTHON_VERSION must be set)
endif

PYTHON_SEMANTIC_RELEASE_SUBCOMMAND := publish
ifneq ($(GIT_BRANCH), $(filter main master, $(GIT_BRANCH)))
    PYTHON_SEMANTIC_RELEASE_SUBCOMMAND := version --noop
endif

PYTHON_RUN := $(DOCKER_RUN) -e GITHUB_TOKEN -v $(PWD):/usr/src/app:Z $(PYTHON_IMAGE):$(PYTHON_VERSION)
PYTHON_RUN_BUILD_ENV := $(DOCKER_RUN_BUILD_ENV) -e GITHUB_TOKEN -v $(PWD):/usr/src/app:Z $(PYTHON_IMAGE):$(PYTHON_VERSION)
PYTHON ?= $(PYTHON_RUN) python

PIP ?= $(PYTHON) -m pip
PIP_INSTALL ?= $(PIP) install --upgrade --user

MYPY ?= $(PYTHON_RUN) mypy --install-types --non-interactive
RUFF ?= $(PYTHON_RUN) ruff
PYTEST ?= $(PYTHON_RUN) pytest
PYTEST_TARGET ?= tests/
PYTEST_REQUIREMENTS ?= .

# Tool versions
MYPY_VERSION ?= 1.*
RUFF_VERSION ?= 0.6.*
PYTEST_VERSION ?= 8.*
PYTHON_SEMANTIC_RELEASE_VERSION ?= 7.*

export

# Add linters (mypy disabled due to pre-existing errors in upstream code)
lint-python:: lint-ruff

clean::
	rm -rf .python

.python:
	@mkdir -p .python
	$(PIP_INSTALL) .

$(REPORTSDIR):
	@mkdir -p $(@)

$(JENKINS_URL_FILE):: $(BUILD_ENV)
	@# python-semantic-release needs JENKINS_URL
	@env | awk '/^JENKINS_URL/ { print }' > $(@)
	@cat $(@) >> $(BUILD_ENV)

.PHONY:format
format: setup-python      ## Format code using ruff
	$(RUFF) format /usr/src/app

.PHONY:lint-mypy
lint-mypy: setup-python ## Run type checking with mypy
	$(PIP_INSTALL) mypy==$(MYPY_VERSION)
	$(MYPY) /usr/src/app/pagerduty_mcp/

.PHONY:lint-ruff
lint-ruff: setup-python ## Run linting with ruff
	$(PIP_INSTALL) ruff==$(RUFF_VERSION)
	$(RUFF) check /usr/src/app

.PHONY:setup-python
setup-python: .python ## Install dependencies

.PHONY:test-pytest
test-pytest: setup-python | $(REPORTSDIR) ## Run pytest suite
	$(PIP_INSTALL) pytest-cov pytest==$(PYTEST_VERSION)
	$(PIP_INSTALL) $(PYTEST_REQUIREMENTS)
	$(PYTEST) /usr/src/app/$(PYTEST_TARGET) \
		--ignore=/usr/src/app/tests/evals/ \
		--cov-report xml:$(REPORTSDIR)/coverage.xml \
		--cov-report term \
		--cov-branch \
		--cov=pagerduty_mcp \
		-o junit_family=xunit2 \
		--junitxml=$(REPORTSDIR)/pytest.junit.xml

.PHONY:version-python
version-python: $(JENKINS_URL_FILE) ## Automatic version increases using python-semantic-release
ifneq (,$(wildcard $(SEMANTIC_RELEASE_CONFIG)))
	$(PIP_INSTALL) python-semantic-release==$(PYTHON_SEMANTIC_RELEASE_VERSION)
	$(PYTHON_RUN_BUILD_ENV) semantic-release $(PYTHON_SEMANTIC_RELEASE_SUBCOMMAND)
endif
