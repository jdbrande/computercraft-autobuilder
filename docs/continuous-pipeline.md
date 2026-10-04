# Automatic production and construction overlap

`build auto <project>` surveys and prepares the site, then issues construction in
verified regions. Builders request finite material batches through their normal
supply stations; miners, harvesters, crafters and processors acquire those batches.
Other prepared builders can place while later batches are being produced.

The controller does not require all schematic materials to fit in central storage
before starting. Material forecasts remain available with `build forecast`.
Expected output cannot be spent: a batch must finish its acquisition and physical
production before it is offered to the builder. Early top-ups respect inventory
capacity, reserved slots and persistent supply ownership.

`build prepare` followed by `build start` retains the explicit full-stock workflow.
Saved automatic projects that already own a full-stock request finish that request;
updating software does not replace their active ownership. Pause/resume and restart
preserve the chosen run behavior. Final verification and worker/cargo settlement
still precede the `built` state.

A worker waits while its own supply batch is acquired and transferred. Fleet-wide
overlap benefits from multiple eligible builders and independent supply stations.
Production requests remain finite and use the existing scheduler; this does not
introduce a new machine, transport or reservation protocol.
