#!/usr/bin/env bash

################################################################################
################################################################################
########### Super-Linter linting Functions @admiralawkbar ######################
################################################################################
################################################################################
########################## FUNCTION CALLS BELOW ################################
################################################################################
################################################################################
#### Function LintCodebase #####################################################
function LintCodebase() {
  # Call comes thorugh as:
  # LintCodebase "${LANGUAGE}" "${LINTER_NAME}" "${LINTER_COMMAND}" "${FILTER_REGEX_INCLUDE}" "${FILTER_REGEX_EXCLUDE}" "${TEST_CASE_RUN}" "${!LANGUAGE_FILE_ARRAY}"
  ####################
  # Pull in the vars #
  ####################
  FILE_TYPE="${1}" && shift            # Pull the variable and remove from array path  (Example: JSON)
  LINTER_NAME="${1}" && shift          # Pull the variable and remove from array path  (Example: jsonlint)
  LINTER_COMMAND="${1}" && shift       # Pull the variable and remove from array path  (Example: jsonlint -c ConfigFile /path/to/file)
  FILTER_REGEX_INCLUDE="${1}" && shift # Pull the variable and remove from array path  (Example: */src/*,*/test/*)
  FILTER_REGEX_EXCLUDE="${1}" && shift # Pull the variable and remove from array path  (Example: */examples/*,*/test/*.test)
  TEST_CASE_RUN="${1}" && shift        # Flag for if running in test cases
  FILE_ARRAY=("$@")                    # Array of files to validate                    (Example: ${FILE_ARRAY_JSON})

  ##########################
  # Initialize empty Array #
  ##########################
  LIST_FILES=()

  ################
  # Set the flag #
  ################
  SKIP_FLAG=0
  INDEX=0

  ############################################################
  # Check to see if we need to go through array or all files #
  ############################################################
  if [ ${#FILE_ARRAY[@]} -eq 0 ]; then
    SKIP_FLAG=1
    debug " - No files found in changeset to lint for language:[${FILE_TYPE}]"
  else
    # We have files added to array of files to check
    LIST_FILES=("${FILE_ARRAY[@]}") # Copy the array into list
  fi

  debug "SKIP_FLAG: ${SKIP_FLAG}, list of files to lint: ${LIST_FILES[*]}"

  ###############################
  # Check if any data was found #
  ###############################
  if [ ${SKIP_FLAG} -eq 0 ]; then
    ########################################
    # Prepare context if TAP format output #
    ########################################
    if IsTAP; then
      TMPFILE=$(mktemp -q "/tmp/super-linter-${FILE_TYPE}.XXXXXX")
      mkdir -p "${REPORT_OUTPUT_FOLDER}"
      REPORT_OUTPUT_FILE="${REPORT_OUTPUT_FOLDER}/super-linter-${FILE_TYPE}.${OUTPUT_FORMAT}"
    fi

    WORKSPACE_PATH="${GITHUB_WORKSPACE}"
    if [ "${TEST_CASE_RUN}" == "true" ]; then
      WORKSPACE_PATH="${GITHUB_WORKSPACE}/${TEST_CASE_FOLDER}"
    fi
    debug "Workspace path: ${WORKSPACE_PATH}"

    ################
    # print header #
    ################
    info ""
    info "----------------------------------------------"
    info "----------------------------------------------"

    debug "Running LintCodebase. FILE_TYPE: ${FILE_TYPE}. Linter name: ${LINTER_NAME}, linter command: ${LINTER_COMMAND}, TEST_CASE_RUN: ${TEST_CASE_RUN}, FILTER_REGEX_INCLUDE: ${FILTER_REGEX_INCLUDE}, FILTER_REGEX_EXCLUDE: ${FILTER_REGEX_EXCLUDE} files to lint: ${FILE_ARRAY[*]}"

    if [ "${TEST_CASE_RUN}" = "true" ]; then
      info "Testing Codebase [${FILE_TYPE}] files..."
    else
      info "Linting [${FILE_TYPE}] files..."
    fi

    info "----------------------------------------------"
    info "----------------------------------------------"

    ##################
    # Lint the files #
    ##################
    for FILE in "${LIST_FILES[@]}"; do
      debug "Linting FILE: ${FILE}"
      ###################################
      # Get the file name and directory #
      ###################################
      FILE_NAME=$(basename "${FILE}" 2>&1)
      DIR_NAME=$(dirname "${FILE}" 2>&1)

      ############################
      # Get the file pass status #
      ############################
      # Example: markdown_good_1.md -> good
      FILE_STATUS=$(echo "${FILE_NAME}" | cut -f2 -d'_')

      ###################
      # Check if docker #
      ###################
      if [[ ${FILE_TYPE} == *"DOCKER"* ]]; then
        debug "FILE_TYPE for FILE ${FILE} is related to Docker: ${FILE_TYPE}"
        if [[ ${FILE} == *"good"* ]]; then
          debug "Setting FILE_STATUS for FILE ${FILE} to 'good'"
          #############
          # Good file #
          #############
          FILE_STATUS='good'
        elif [[ ${FILE} == *"bad"* ]]; then
          debug "Setting FILE_STATUS for FILE ${FILE} to 'bad'"
          ############
          # Bad file #
          ############
          FILE_STATUS='bad'
        fi
      fi

      #######################################
      # Check if Cargo.toml for Rust Clippy #
      #######################################
      if [[ ${FILE_TYPE} == *"RUST"* ]] && [[ ${LINTER_NAME} == "clippy" ]]; then
        debug "FILE_TYPE for FILE ${FILE} is related to Rust Clippy: ${FILE_TYPE}"
        if [[ ${FILE} == *"good"* ]]; then
          debug "Setting FILE_STATUS for FILE ${FILE} to 'good'"
          #############
          # Good file #
          #############
          FILE_STATUS='good'
        elif [[ ${FILE} == *"bad"* ]]; then
          debug "Setting FILE_STATUS for FILE ${FILE} to 'bad'"
          ############
          # Bad file #
          ############
          FILE_STATUS='bad'
        fi
      fi

      #########################################################
      # If not found, assume it should be linted successfully #
      #########################################################
      if [ -z "${FILE_STATUS}" ] || { [ "${FILE_STATUS}" != "good" ] && [ "${FILE_STATUS}" != "bad" ]; }; then
        debug "FILE_STATUS (${FILE_STATUS}) is empty, or not set to 'good' or 'bad'. Assuming it should be linted correctly. Setting FILE_STATUS to 'good'..."
        FILE_STATUS="good"
      fi

      INDIVIDUAL_TEST_FOLDER="${FILE_TYPE,,}" # Folder for specific tests. By convention, it's the lowercased FILE_TYPE

      debug "File: ${FILE}, FILE_NAME: ${FILE_NAME}, DIR_NAME:${DIR_NAME}, FILE_STATUS: ${FILE_STATUS}, INDIVIDUAL_TEST_FOLDER: ${INDIVIDUAL_TEST_FOLDER}"

      if [[ ${FILE} != *"${TEST_CASE_FOLDER}/${INDIVIDUAL_TEST_FOLDER}/"* ]] && [ "${TEST_CASE_RUN}" == "true" ]; then
        debug "Skipping ${FILE} because it's not in the test case directory for ${FILE_TYPE}..."
        continue
      fi

      ##################################
      # Increase the linted file index #
      ##################################
      (("INDEX++"))

      ##############
      # File print #
      ##############
      info "---------------------------"
      info "File:[${FILE}]"

      #################################
      # Add the language to the array #
      #################################
      LINTED_LANGUAGES_ARRAY+=("${FILE_TYPE}")

      ####################
      # Set the base Var #
      ####################
      LINT_CMD=''

      #####################
      # Check for ansible #
      #####################
      if [[ ${FILE_TYPE} == "ANSIBLE" ]]; then
        #########################################
        # Make sure we don't lint certain files #
        #########################################
        if [[ ${FILE} == *"vault.yml"* ]] || [[ ${FILE} == *"galaxy.yml"* ]]; then
          # This is a file we don't look at
          continue
        fi

        ################################
        # Lint the file with the rules #
        ################################
        LINT_CMD=$(
          cd "${ANSIBLE_DIRECTORY}" || exit
          ${LINTER_COMMAND} "${FILE}" 2>&1
        )
      ####################################
      # Corner case for pwsh subshell    #
      #  - PowerShell (PSScriptAnalyzer) #
      #  - ARM        (arm-ttk)          #
      ####################################
      elif [[ ${FILE_TYPE} == "POWERSHELL" ]] || [[ ${FILE_TYPE} == "ARM" ]]; then
        ################################
        # Lint the file with the rules #
        ################################
        # Need to run PowerShell commands using pwsh -c, also exit with exit code from inner subshell
        LINT_CMD=$(
          cd "${WORKSPACE_PATH}" || exit
          pwsh -NoProfile -NoLogo -Command "${LINTER_COMMAND} \"${FILE}\"; if (\${Error}.Count) { exit 1 }"
          exit $? 2>&1
        )
      ###############################################################################
      # Corner case for groovy as we have to pass it as path and file in ant format #
      ###############################################################################
      elif [[ ${FILE_TYPE} == "GROOVY" ]]; then
        #######################################
        # Lint the file with the updated path #
        #######################################
        LINT_CMD=$(
          cd "${WORKSPACE_PATH}" || exit
          ${LINTER_COMMAND} --path "${DIR_NAME}" --files "$FILE_NAME" 2>&1
        )
      ###############################################################################
      # Corner case for R as we have to pass it to R                                #
      ###############################################################################
      elif [[ ${FILE_TYPE} == "R" ]]; then
        #######################################
        # Lint the file with the updated path #
        #######################################
        if [ ! -f "${DIR_NAME}/.lintr" ]; then
          r_dir="${WORKSPACE_PATH}"
        else
          r_dir="${DIR_NAME}"
        fi
        LINT_CMD=$(
          cd "$r_dir" || exit
          R --slave -e "lints <- lintr::lint('$FILE');print(lints);errors <- purrr::keep(lints, ~ .\$type == 'error');quit(save = 'no', status = if (length(errors) > 0) 1 else 0)" 2>&1
        )
      #########################################################
      # Corner case for C# as it writes to tty and not stdout #
      #########################################################
      elif [[ ${FILE_TYPE} == "CSHARP" ]]; then
        LINT_CMD=$(
          cd "${DIR_NAME}" || exit
          ${LINTER_COMMAND} "${FILE_NAME}" | tee /dev/tty2 2>&1
          exit "${PIPESTATUS[0]}"
        )
      #########################################################
      # Corner case for CFN_NAG as path is passed inside a flag #
      #########################################################
      elif [[ ${FILE_TYPE} == "CLOUDFORMATION_CFN_NAG" ]]; then
        LINT_CMD=$(
          cd "${WORKSPACE_PATH}" || exit
          ${LINTER_COMMAND} --input-path="${FILE}" 2>&1
        )
      #######################################################
      # Corner case for KTLINT as it cant use the full path #
      #######################################################
      elif [[ ${FILE_TYPE} == "KOTLIN" ]]; then
        LINT_CMD=$(
          cd "${DIR_NAME}" || exit
          ${LINTER_COMMAND} "${FILE_NAME}" 2>&1
        )
      ######################################################
      # Corner case for GITLEAKS:                          #
      # - Path to the file to scan is passed inside a flag #
      # - Output report is written to a file               #
      ######################################################
      elif [[ ${FILE_TYPE} == "GITLEAKS" ]]; then
        LINT_CMD=$(
          cd "${WORKSPACE_PATH}" || exit
          ${LINTER_COMMAND} --path="${FILE}" --report="/dev/stdout"
        )
      ################################
      # Lint the file with the rules #
      ################################
      else
        LINT_CMD=$(
          cd "${WORKSPACE_PATH}" || exit
          ${LINTER_COMMAND} "${FILE}" 2>&1
        )
      fi
      #######################
      # Load the error code #
      #######################
      ERROR_CODE=$?

      ########################################
      # Check for if it was supposed to pass #
      ########################################
      if [[ ${FILE_STATUS} == "good" ]]; then
        ##############################
        # Check the shell for errors #
        ##############################
        if [ ${ERROR_CODE} -ne 0 ]; then
          debug "Found errors. Error code: ${ERROR_CODE}, File type: ${FILE_TYPE}, Error on missing exec bit: ${ERROR_ON_MISSING_EXEC_BIT}"
          if [[ ${FILE_TYPE} == "BASH_EXEC" ]] && [[ "${ERROR_ON_MISSING_EXEC_BIT}" == "false" ]]; then
            ########
            # WARN #
            ########
            warn "Warnings found in [${LINTER_NAME}] linter!"
            warn "${LINT_CMD}"

            if IsLintly && SupportsLintly "${FILE_TYPE}"; then
              InvokeLintly "${LINTLY_SUPPORT_ARRAY[${FILE_TYPE}]}" "${FILE}" "${LINT_CMD}"
            fi

          else
            #########
            # Error #
            #########
            error "Found errors in [${LINTER_NAME}] linter!"
            error "Error code: ${ERROR_CODE}. Command output:${NC}\n------\n${LINT_CMD}\n------"

            if IsLintly && SupportsLintly "${FILE_TYPE}"; then
              InvokeLintly "${LINTLY_SUPPORT_ARRAY[${FILE_TYPE}]}" "${FILE}" "${LINT_CMD}"
            fi

            # Increment the error count
            (("ERRORS_FOUND_${FILE_TYPE}++"))
          fi

          #######################################################
          # Store the linting as a temporary file in TAP format #
          #######################################################
          if IsTAP; then
            NotOkTap "${INDEX}" "${FILE_NAME}" "${TMPFILE}"
            AddDetailedMessageIfEnabled "${LINT_CMD}" "${TMPFILE}"
          fi
        else
          ###########
          # Success #
          ###########
          info " - File:${F[W]}[${FILE_NAME}]${F[B]} was linted with ${F[W]}[${LINTER_NAME}]${F[B]} successfully"

          #######################################################
          # Store the linting as a temporary file in TAP format #
          #######################################################
          if IsTAP; then
            OkTap "${INDEX}" "${FILE_NAME}" "${TMPFILE}"
          fi
        fi
      else
        #######################################
        # File status = bad, this should fail #
        #######################################
        ##############################
        # Check the shell for errors #
        ##############################
        if [ ${ERROR_CODE} -eq 0 ]; then
          #########
          # Error #
          #########
          error "Found errors in [${LINTER_NAME}] linter!"
          error "This file should have failed test case!"
          error "Error code: ${ERROR_CODE}. Command output:${NC}\n------\n${LINT_CMD}\n------"
          # Increment the error count
          (("ERRORS_FOUND_${FILE_TYPE}++"))
        else
          ###########
          # Success #
          ###########
          info " - File:${F[W]}[${FILE_NAME}]${F[B]} failed test case (Error code: ${ERROR_CODE}) with ${F[W]}[${LINTER_NAME}]${F[B]} successfully"
        fi

        #######################################################
        # Store the linting as a temporary file in TAP format #
        #######################################################
        if IsTAP; then
          NotOkTap "${INDEX}" "${FILE_NAME}" "${TMPFILE}"
          AddDetailedMessageIfEnabled "${LINT_CMD}" "${TMPFILE}"
        fi
      fi
      debug "Error code: ${ERROR_CODE}. Command output:${NC}\n------\n${LINT_CMD}\n------"
    done

    #################################
    # Generate report in TAP format #
    #################################
    if IsTAP && [ ${INDEX} -gt 0 ]; then
      HeaderTap "${INDEX}" "${REPORT_OUTPUT_FILE}"
      cat "${TMPFILE}" >>"${REPORT_OUTPUT_FILE}"

      if [ "${TEST_CASE_RUN}" = "true" ]; then
        ########################################################################
        # If expected TAP report exists then compare with the generated report #
        ########################################################################
        TAP_SUCCESS=0
        TAP_ERROR_ARRAY=()
        mapfile -t EXPECTED_FILES_ARRAY < <(
          cd "${WORKSPACE_PATH}/${INDIVIDUAL_TEST_FOLDER}/reports" || exit 1
          find . -name '*.tap' 2>&1
        )
        for EXPECTED_FILE in "${EXPECTED_FILES_ARRAY[@]}"; do
          # Remove the pathing to file name
          EXPECTED_FILE_NAME="${EXPECTED_FILE:2}"
          # Create full path
          EXPECTED_FILE="${WORKSPACE_PATH}/${INDIVIDUAL_TEST_FOLDER}/reports/${EXPECTED_FILE_NAME}"

          # Check that file exists
          if [ -e "${EXPECTED_FILE}" ]; then
            TMPFILE=$(mktemp -q "/tmp/diff-${FILE_TYPE}.XXXXXX")
            ## Ignore white spaces, case sensitive
            if ! diff -a -w -i "${EXPECTED_FILE}" "${REPORT_OUTPUT_FILE}" >"${TMPFILE}" 2>&1; then
              #############################################
              # We failed to compare the reporting output #
              #############################################
              warn "Tap File difference:"
              cat "${TMPFILE}"
              STRING=$(cat "${TMPFILE}")
              TAP_ERROR_ARRAY+=("${STRING}")
              TAP_ERROR_ARRAY+=("Failed to assert TAP output for ${LINTER_NAME} linter")
            else
              info "TAP output validated successfully for ${LINTER_NAME}"
              # Set flag for success
              TAP_SUCCESS=1
            fi
          else
            fatal "No TAP expected file found at:[${EXPECTED_FILE}]"
          fi
        done

        # Need to check if the TAP_SUCCESS was set to 1
        if [ "${TAP_SUCCESS}" -ne 1 ]; then
          # We failed on all tap outputs
          error "Failed to assert TAP output!"
          for LINE in "${TAP_ERROR_ARRAY[@]}"; do
            error "${LINE}"
          done
          fatal "Failed to assert TAP output!"
        fi
      fi
    fi
  fi

  ##############################
  # Validate we ran some tests #
  ##############################
  if [ "${TEST_CASE_RUN}" = "true" ] && [ "${INDEX}" -eq 0 ]; then
    #################################################
    # We failed to find files and no tests were ran #
    #################################################
    error "Failed to find any tests ran for the Linter:[${LINTER_NAME}]!"
    fatal "Please validate logic or that tests exist!"
  fi
}
