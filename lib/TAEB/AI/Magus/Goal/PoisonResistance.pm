package TAEB::AI::Magus::Goal::PoisonResistance;
use Moose;
extends 'TAEB::AI::Magus::Goal';

sub met_when { TAEB->senses->poison_resistant }

1;

