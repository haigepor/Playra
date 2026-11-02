package com.kyant.backdrop.catalog.utils

import kotlinx.coroutines.android.awaitFrame as awaitAndroidFrame

suspend fun awaitFrame() {
    awaitAndroidFrame()
}
