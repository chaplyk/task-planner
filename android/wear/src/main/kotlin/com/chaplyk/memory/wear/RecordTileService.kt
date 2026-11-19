package com.chaplyk.memory.wear

import androidx.wear.protolayout.ActionBuilders
import androidx.wear.protolayout.ActionBuilders.AndroidBooleanExtra
import androidx.wear.protolayout.ColorBuilders.argb
import androidx.wear.protolayout.DimensionBuilders.dp
import androidx.wear.protolayout.DimensionBuilders.expand
import androidx.wear.protolayout.DimensionBuilders.sp
import androidx.wear.protolayout.LayoutElementBuilders
import androidx.wear.protolayout.ModifiersBuilders
import androidx.wear.protolayout.ResourceBuilders
import androidx.wear.protolayout.TimelineBuilders
import androidx.wear.tiles.RequestBuilders
import androidx.wear.tiles.TileBuilders
import androidx.wear.tiles.TileService
import com.google.common.util.concurrent.Futures
import com.google.common.util.concurrent.ListenableFuture

/// The Tile next to the watch face: a big mic button that opens [RecordActivity] listening.
class RecordTileService : TileService() {
    private companion object {
        const val RESOURCES_VERSION = "1"
        const val MIC = "mic"
        const val ACCENT = 0xFF4F6BED.toInt()
        const val TEXT = 0xFFFFFFFF.toInt()
    }

    override fun onTileRequest(requestParams: RequestBuilders.TileRequest): ListenableFuture<TileBuilders.Tile> {
        val tile = TileBuilders.Tile.Builder()
            .setResourcesVersion(RESOURCES_VERSION)
            .setTileTimeline(TimelineBuilders.Timeline.fromLayoutElement(layout()))
            .build()
        return Futures.immediateFuture(tile)
    }

    override fun onTileResourcesRequest(
        requestParams: RequestBuilders.ResourcesRequest,
    ): ListenableFuture<ResourceBuilders.Resources> {
        val mic = ResourceBuilders.ImageResource.Builder()
            .setAndroidResourceByResId(
                ResourceBuilders.AndroidImageResourceByResId.Builder().setResourceId(R.drawable.ic_mic).build(),
            )
            .build()
        return Futures.immediateFuture(
            ResourceBuilders.Resources.Builder()
                .setVersion(RESOURCES_VERSION)
                .addIdToImageMapping(MIC, mic)
                .build(),
        )
    }

    private fun layout(): LayoutElementBuilders.LayoutElement {
        val record = ModifiersBuilders.Clickable.Builder()
            .setId("record")
            .setOnClick(
                ActionBuilders.LaunchAction.Builder()
                    .setAndroidActivity(
                        ActionBuilders.AndroidActivity.Builder()
                            .setPackageName(packageName)
                            .setClassName(RecordActivity::class.java.name)
                            .addKeyToExtraMapping(
                                RecordActivity.EXTRA_AUTOSTART,
                                AndroidBooleanExtra.Builder().setValue(true).build(),
                            )
                            .build(),
                    )
                    .build(),
            )
            .build()

        val micButton = LayoutElementBuilders.Box.Builder()
            .setWidth(dp(84f))
            .setHeight(dp(84f))
            .setModifiers(
                ModifiersBuilders.Modifiers.Builder()
                    .setClickable(record)
                    .setBackground(
                        ModifiersBuilders.Background.Builder()
                            .setColor(argb(ACCENT))
                            .setCorner(ModifiersBuilders.Corner.Builder().setRadius(dp(42f)).build())
                            .build(),
                    )
                    .setSemantics(ModifiersBuilders.Semantics.Builder().setContentDescription("Record a reminder").build())
                    .build(),
            )
            .addContent(
                LayoutElementBuilders.Image.Builder()
                    .setResourceId(MIC)
                    .setWidth(dp(40f))
                    .setHeight(dp(40f))
                    .build(),
            )
            .build()

        val column = LayoutElementBuilders.Column.Builder()
            .setHorizontalAlignment(LayoutElementBuilders.HORIZONTAL_ALIGN_CENTER)
            .addContent(text("New reminder", 15f, TEXT, maxLines = 1))
            .addContent(spacer(10f))
            .addContent(micButton)

        return LayoutElementBuilders.Box.Builder()
            .setWidth(expand())
            .setHeight(expand())
            .setModifiers(
                ModifiersBuilders.Modifiers.Builder()
                    .setPadding(ModifiersBuilders.Padding.Builder().setStart(dp(24f)).setEnd(dp(24f)).build())
                    .build(),
            )
            .addContent(column.build())
            .build()
    }

    private fun text(value: String, size: Float, color: Int, maxLines: Int) =
        LayoutElementBuilders.Text.Builder()
            .setText(value)
            .setMaxLines(maxLines)
            .setMultilineAlignment(LayoutElementBuilders.TEXT_ALIGN_CENTER)
            .setFontStyle(LayoutElementBuilders.FontStyle.Builder().setSize(sp(size)).setColor(argb(color)).build())
            .build()

    private fun spacer(height: Float) = LayoutElementBuilders.Spacer.Builder().setHeight(dp(height)).build()
}
