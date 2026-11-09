# Update Script Refactoring TODO

## Priority 1 - Critical Issues

- [ ] **Extract spinner logic to reusable function**
  - Lines: 68-97, 159-165, 199-204 (duplicate code)
  - Create single `spinner()` function to eliminate code duplication
  - All spinners should follow same pattern

- [ ] **Centralize temp file cleanup**
  - Lines: 155, 195 (mktemp without guaranteed cleanup)
  - Add trap handler: `trap "rm -f $tmp_file" RETURN EXIT`
  - Prevents orphaned temp files on early exit or error

- [ ] **Fix error handling in NPM/PIP spinners**
  - Lines: 176-186, 216-219
  - Current spinner doesn't properly capture command failures
  - Ensure exit codes are propagated correctly

## Priority 2 - Standardization & Configuration

- [ ] **Remove duplicate color definitions**
  - Lines: 19-36 (NC and RESET both defined, RESET is correct)
  - Source from standard location if possible (wallctl/colors.sh)
  - Keep consistent naming convention

- [ ] **Create external config file**
  - Location: `~/.config/groot/update.conf`
  - Extract hard-coded values:
    - Mirror countries (lines 143, 263)
    - Reflector options (age, count, protocol)
    - Cache retention settings
    - Log file path

- [ ] **Standardize function naming**
  - Inconsistent: `update_*` vs `phase_*` vs `print_*` vs `run_with_*`
  - Establish convention and rename accordingly
  - Consider grouping: display functions, update functions, helper functions

- [ ] **Add --help flag**
  - Document usage, options, and distro support
  - Include examples: `update --mirrors`, `update --help`

## Priority 3 - Code Quality

- [ ] **Consistent indentation**
  - Currently mixed 2/4 spaces
  - Choose standard and refactor entire file

- [ ] **Improve comments**
  - Add brief explanation for lock file mechanism (lines 100-116)
  - Document why distro detection is needed (lines 121-126)

- [ ] **Enhance spinner progress**
  - Show percentage or step count (e.g., "Package 3/12")
  - Add timing information

- [ ] **Separate concerns with helper library**
  - Create: `~/.local/lib/update-helpers.sh`
  - Move: spinner, lock management, temp file handling
  - Import into update script: `source ~/.local/lib/update-helpers.sh`

- [ ] **Add verbose/debug mode**
  - Flag: `--verbose` or `-v`
  - Output full command output instead of just logging

## Testing

- [ ] Test on Arch Linux with file conflicts
- [ ] Test on non-Arch distro (early returns)
- [ ] Test interrupt handling (Ctrl+C cleanup)
- [ ] Test with no internet connection
- [ ] Test concurrent update attempts (lock file)

## Documentation

- [ ] Add inline documentation for complex functions
- [ ] Create README with usage examples
- [ ] Document each phase and what it does
- [ ] Add troubleshooting section
