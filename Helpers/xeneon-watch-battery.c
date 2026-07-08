#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include <libimobiledevice/companion_proxy.h>
#include <libimobiledevice/libimobiledevice.h>
#include <plist/plist.h>

static const char *registry_keys[] = {
    "BatteryCurrentCapacity",
    "BatteryIsCharging",
    "BatteryPercent",
    "BatteryLevel",
    "CurrentBatteryCapacity",
    "DeviceName",
    "Name",
    "ProductName",
    "MarketingName",
    "ProductType",
    "DeviceClass",
    "ProductVersion",
    "BuildVersion",
    "SerialNumber",
    "ModelNumber",
    NULL
};

static int open_companion_client(const char *udid, idevice_t *device, companion_proxy_client_t *companion) {
    *device = NULL;
    *companion = NULL;

    idevice_error_t device_error = idevice_new_with_options(
        device,
        udid,
        IDEVICE_LOOKUP_USBMUX | IDEVICE_LOOKUP_NETWORK | IDEVICE_LOOKUP_PREFER_NETWORK
    );
    if (device_error != IDEVICE_E_SUCCESS || !*device) {
        return 1;
    }

    companion_proxy_error_t companion_error = companion_proxy_client_start_service(
        *device,
        companion,
        "XENEON Edge Widgets"
    );
    if (companion_error != COMPANION_PROXY_E_SUCCESS || !*companion) {
        idevice_free(*device);
        *device = NULL;
        return 1;
    }

    return 0;
}

static void close_companion_client(idevice_t device, companion_proxy_client_t companion) {
    if (companion) {
        companion_proxy_client_free(companion);
    }
    if (device) {
        idevice_free(device);
    }
}

static int get_registry_for_udid(const char *udid, plist_t *registry) {
    idevice_t device = NULL;
    companion_proxy_client_t companion = NULL;

    if (open_companion_client(udid, &device, &companion) != 0) {
        return 1;
    }

    companion_proxy_error_t companion_error = companion_proxy_get_device_registry(companion, registry);
    close_companion_client(device, companion);
    return companion_error == COMPANION_PROXY_E_SUCCESS && *registry ? 0 : 1;
}

static plist_t get_value_for_companion(const char *phone_udid, const char *watch_udid, const char *key) {
    idevice_t device = NULL;
    companion_proxy_client_t companion = NULL;
    plist_t value = NULL;

    if (open_companion_client(phone_udid, &device, &companion) != 0) {
        return NULL;
    }

    companion_proxy_error_t error = companion_proxy_get_value_from_registry(
        companion,
        watch_udid,
        key,
        &value
    );
    close_companion_client(device, companion);

    if (error != COMPANION_PROXY_E_SUCCESS || !value) {
        return NULL;
    }
    return value;
}

static int print_plist_json(plist_t plist) {
    char *json = NULL;
    uint32_t length = 0;
    plist_err_t plist_error = plist_to_json(plist, &json, &length, 1);
    if (plist_error == PLIST_ERR_SUCCESS && json && length > 0) {
        fwrite(json, 1, length, stdout);
        free(json);
        return 0;
    }
    if (json) {
        free(json);
    }
    return 1;
}

static void print_json_string(const char *value) {
    fputc('"', stdout);
    for (const char *cursor = value; *cursor; cursor++) {
        if (*cursor == '"' || *cursor == '\\') {
            fputc('\\', stdout);
        }
        fputc(*cursor, stdout);
    }
    fputc('"', stdout);
}

static int print_watch_values_for_udid(const char *phone_udid) {
    plist_t registry = NULL;
    if (get_registry_for_udid(phone_udid, &registry) != 0) {
        return 1;
    }

    uint32_t watch_count = plist_array_get_size(registry);
    if (watch_count == 0) {
        plist_free(registry);
        return 1;
    }

    fputc('[', stdout);
    int printed_watch = 0;

    for (uint32_t watch_index = 0; watch_index < watch_count; watch_index++) {
        plist_t watch_node = plist_array_get_item(registry, watch_index);
        if (!watch_node || plist_get_node_type(watch_node) != PLIST_STRING) {
            continue;
        }

        char *watch_udid = NULL;
        plist_get_string_val(watch_node, &watch_udid);
        if (!watch_udid) {
            continue;
        }

        if (printed_watch) {
            fputc(',', stdout);
        }
        printed_watch = 1;

        fputs("{\"CompanionUDID\":", stdout);
        print_json_string(watch_udid);

        for (int key_index = 0; registry_keys[key_index] != NULL; key_index++) {
            const char *key = registry_keys[key_index];
            plist_t value = get_value_for_companion(phone_udid, watch_udid, key);
            if (!value) {
                continue;
            }

            fputc(',', stdout);
            print_json_string(key);
            fputc(':', stdout);
            if (print_plist_json(value) != 0) {
                fputs("null", stdout);
            }
            plist_free(value);
        }

        fputc('}', stdout);
        free(watch_udid);
    }

    fputc(']', stdout);
    fputc('\n', stdout);
    plist_free(registry);
    return printed_watch ? 0 : 1;
}

int main(int argc, char **argv) {
    if (argc > 1 && argv[1] && strlen(argv[1]) > 0) {
        return print_watch_values_for_udid(argv[1]);
    }

    idevice_info_t *devices = NULL;
    int count = 0;
    idevice_error_t list_error = idevice_get_device_list_extended(&devices, &count);
    if (list_error != IDEVICE_E_SUCCESS || !devices || count <= 0) {
        return 1;
    }

    int exit_code = 1;
    for (int index = 0; devices[index] != NULL; index++) {
        if (!devices[index]->udid) {
            continue;
        }
        if (print_watch_values_for_udid(devices[index]->udid) == 0) {
            exit_code = 0;
            break;
        }
    }

    idevice_device_list_extended_free(devices);
    return exit_code;
}
