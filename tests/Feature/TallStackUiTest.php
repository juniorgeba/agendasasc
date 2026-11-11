<?php

use Illuminate\Support\Facades\Blade;

it('renders TallStackUI components inside the base layout with its script and Livewire assets', function () {
    $html = Blade::render('<x-layouts::app><x-button text="Salvar" /></x-layouts::app>');

    expect($html)
        ->toContain('/tallstackui/script/')
        ->toContain('<button')
        ->toContain('Salvar')
        ->toContain('livewire.js');
});

it('loads the TallStackUI script before the Vite assets', function () {
    $html = Blade::render('<x-layouts::app>conteúdo</x-layouts::app>');

    // Build (`/build/assets/`) ou dev server do Vite (`/resources/css/app.css`).
    preg_match('#/build/assets/|/resources/css/app\.css#', $html, $viteMatch, PREG_OFFSET_CAPTURE);

    expect($viteMatch)->not->toBeEmpty()
        ->and(strpos($html, '/tallstackui/script/'))->toBeLessThan($viteMatch[0][1]);
});
