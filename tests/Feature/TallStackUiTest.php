<?php

use Illuminate\Support\Facades\Blade;
use Illuminate\Support\Facades\Vite;

/**
 * Aponta o Vite para um "hot file" falso, para os testes não dependerem de `npm run build`
 * nem do `npm run dev` estar rodando.
 */
beforeEach(function () {
    $hotFile = tempnam(sys_get_temp_dir(), 'vite-hot');
    file_put_contents($hotFile, 'http://vite.test');

    Vite::useHotFile($hotFile);
});

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

    $vitePosition = strpos($html, 'http://vite.test/resources/css/app.css');

    expect($vitePosition)->not->toBeFalse()
        ->and(strpos($html, '/tallstackui/script/'))->toBeLessThan($vitePosition);
});
