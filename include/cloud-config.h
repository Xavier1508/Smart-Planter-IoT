#pragma once

// Optional local provisioning. The file is ignored by Git and is never needed
// for host tests or local-only builds.
#if __has_include("cloud-secret.local.h")
#include "cloud-secret.local.h"
#endif

#ifndef MOSS_CLOUD_ENABLED
#define MOSS_CLOUD_ENABLED 0
#endif

#ifndef MOSS_SUPABASE_URL
#define MOSS_SUPABASE_URL "https://sxrxhslnunlvjsiwfzjm.supabase.co"
#endif

#ifndef MOSS_WIFI_SSID
#define MOSS_WIFI_SSID ""
#endif

#ifndef MOSS_WIFI_PASSWORD
#define MOSS_WIFI_PASSWORD ""
#endif

#ifndef MOSS_DEVICE_ID
#define MOSS_DEVICE_ID ""
#endif

#ifndef MOSS_DEVICE_TOKEN
#define MOSS_DEVICE_TOKEN ""
#endif

#ifndef MOSS_DEVICE_CLAIM_CODE
#define MOSS_DEVICE_CLAIM_CODE ""
#endif

#ifndef MOSS_DEVICE_NAME
#define MOSS_DEVICE_NAME "Tunas Planter"
#endif
