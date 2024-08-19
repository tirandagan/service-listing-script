#!/bin/bash

# ANSI color codes
RESET="\033[0m"
BOLD="\033[1m"
BLUE="\033[34m"
WHITE="\033[37m"
GREEN="\033[32m"
YELLOW="\033[33m"

# Function to display help message
show_help() {
    echo "Usage: $0 [OPTION]"
    echo "List system services and their status."
    echo
    echo "Options:"
    echo "  --all       Show all services (both active and inactive)"
    echo "  --active    Show only active services (default)"
    echo "  --inactive  Show only inactive services"
    echo "  --help      Display this help message and exit"
    echo
    echo "If no option is provided, only active services are shown."
}

# Function to wrap text to a specific width
wrap_text() {
    local text="$1"
    local width=$2
    echo "$text" | fold -s -w $width | sed '2,$s/^/  /'
}

# Function to format runtime
format_runtime() {
    local seconds=$1
    local days=$((seconds / 86400))
    local hours=$(( (seconds % 86400) / 3600 ))
    local minutes=$(( (seconds % 3600) / 60 ))
    local secs=$((seconds % 60))
    printf "%dd %02dh:%02dm:%02ds" $days $hours $minutes $secs
}

# Function to calculate runtime
calculate_runtime() {
    local active_timestamp="$1"
    if [ "$active_timestamp" == "N/A" ]; then
        echo "N/A"
        return
    fi
    local now=$(date +%s)
    local active_time=$(date -d "$active_timestamp" +%s)
    local runtime=$((now - active_time))
    format_runtime $runtime
}

# Function to print the table header
print_header() {
    printf "${BLUE}┌─────────────────────────┬──────────┬─────────────────┬──────────────────────────────────────────────────┐${RESET}\n"
    printf "${BLUE}│${WHITE}%-25s${BLUE}│${WHITE}%-10s${BLUE}│${WHITE}%-17s${BLUE}│${WHITE}%-50s${BLUE}│${RESET}\n" "Service" "Enabled" "Runtime" "Description"
    printf "${BLUE}├─────────────────────────┼──────────┼─────────────────┼──────────────────────────────────────────────────┤${RESET}\n"
}

# Function to print service details
print_service() {
    local service="$1" enabled="$2" runtime="$3" description="$4"
    local wrapped_service=$(wrap_text "$service" 23)
    local wrapped_description=$(wrap_text "$description" 48)
    
    IFS=$'\n' read -d '' -r -a service_lines <<< "$wrapped_service"
    IFS=$'\n' read -d '' -r -a desc_lines <<< "$wrapped_description"
    
    local max_lines=$(( ${#service_lines[@]} > ${#desc_lines[@]} ? ${#service_lines[@]} : ${#desc_lines[@]} ))
    
    for i in $(seq 0 $((max_lines - 1))); do
        if [ $i -eq 0 ]; then
            printf "${BLUE}│${WHITE}%-25s${BLUE}│" "${service_lines[$i]}"
            if [ "$enabled" == "enabled" ]; then
                printf "${GREEN}%-10s${BLUE}│" "$enabled"
            else
                printf "${YELLOW}%-10s${BLUE}│" "$enabled"
            fi
            printf "${WHITE}%-17s${BLUE}│${WHITE}%-50s${BLUE}│${RESET}\n" "$runtime" "${desc_lines[$i]:-}"
        else
            printf "${BLUE}│${WHITE}%-25s${BLUE}│%-10s│%-17s│${WHITE}%-50s${BLUE}│${RESET}\n" "${service_lines[$i]:-}" "" "" "${desc_lines[$i]:-}"
        fi
    done
}

# Function to print the table footer
print_footer() {
    printf "${BLUE}└─────────────────────────┴──────────┴─────────────────┴──────────────────────────────────────────────────┘${RESET}\n"
}

# Function to print a horizontal separator
print_separator() {
    printf "${BLUE}├─────────────────────────┼──────────┼─────────────────┼──────────────────────────────────────────────────┤${RESET}\n"
}

# Function to process and print a group of services
print_group() {
    local status=$1 group_services=$2
    [[ -z "$group_services" ]] && return

    echo -e "\n${BOLD}${WHITE}Services with status: ${status}${RESET}"
    print_header

    # Sort services and split into disabled and other
    local disabled_services=()
    local other_services=()

    while read -r service; do
        enabled=$(systemctl is-enabled "${service}.service" 2>/dev/null)
        if [[ "$enabled" == "disabled" ]]; then
            disabled_services+=("$service")
        else
            other_services+=("$service")
        fi
    done < <(echo "$group_services" | tr ' ' '\n' | sort)

    # Print other services first
    for service in "${other_services[@]}"; do
        print_service_details "$service"
    done

    # Print separator if there are both types of services
    if [[ ${#disabled_services[@]} -gt 0 && ${#other_services[@]} -gt 0 ]]; then
        print_separator
    fi

    # Print disabled services
    for service in "${disabled_services[@]}"; do
        print_service_details "$service"
    done

    print_footer
}

# Function to print service details
print_service_details() {
    local service=$1
    local enabled=$(systemctl is-enabled "${service}.service" 2>/dev/null)
    local description=$(systemctl show -p Description "${service}.service" 2>/dev/null | cut -d'=' -f2-)
    local active_timestamp=$(systemctl show -p ActiveEnterTimestamp "${service}.service" 2>/dev/null | cut -d'=' -f2-)
    local runtime=$(calculate_runtime "$active_timestamp")
    
    # Truncate 'enabled' status to fit in the column
    enabled="${enabled:0:10}"
    
    # Replace special characters in service name
    service=$(echo "$service" | tr -cd '[:print:]')
    
    print_service "$service" "$enabled" "$runtime" "$description"
}

# Default to showing only active services
show_active=true
show_inactive=false

# Parse command-line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --all)
            show_active=true
            show_inactive=true
            shift
            ;;
        --active)
            show_active=true
            show_inactive=false
            shift
            ;;
        --inactive)
            show_active=false
            show_inactive=true
            shift
            ;;
        --help)
            show_help
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            echo "Use --help for usage information."
            exit 1
            ;;
    esac
done

# Get the list of all services
services=$(systemctl list-units --type=service --all --no-legend | awk '{print $1}' | sed 's/\.service$//')

# Arrays to store services by status
declare -A service_groups

# Populate service groups
while read -r service; do
    status=$(systemctl is-active "${service}.service" 2>/dev/null)
    service_groups[$status]+="$service "
done <<< "$services"

# Print services grouped by status
if $show_active; then
    print_group "active" "${service_groups[active]}"
fi

if $show_inactive; then
    print_group "inactive" "${service_groups[inactive]}"
    print_group "failed" "${service_groups[failed]}"

    # Print any other status groups
    for status in "${!service_groups[@]}"; do
        if [[ "$status" != "active" && "$status" != "inactive" && "$status" != "failed" ]]; then
            print_group "$status" "${service_groups[$status]}"
        fi
    done
fi
