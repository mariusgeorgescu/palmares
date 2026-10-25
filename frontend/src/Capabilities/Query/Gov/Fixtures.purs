-- | Fixturile de citire, separate de `Mock.purs` ca acela să rămână doar cablaj.
-- |
-- | __Fiecare e un payload măsurat, nu inventat.__ Se obține interogând serviciul care rulează și se
-- | lipește aici neatins. Unde un array real e lung (top 10 DRep-i, 5 acțiuni care se închid), se
-- | păstrează primele câteva elemente — e tot date reale, doar mai puține rânduri. Ce __nu__ se
-- | taie: `participation_by_epoch` (20 de puncte, cât cere graficul) și cele două desfășurări de
-- | acțiuni, pentru că numărul lor de categorii e el însuși un fapt de verificat.
module Capabilities.Query.Gov.Fixtures
  ( statusFixture
  , dashboardFixture
  , drepExplorerFixture
  , drepDetailFixture
  ) where

-- | `GET /status` pe preprod, 2026-10-24. `epoch_params` e omis: niciun decodor nu-l citește încă,
-- | iar ecranul de Metodologie își va aduce propriul DTO.
statusFixture :: String
statusFixture =
  """
  { "network": "preprod"
  , "governance":
      { "epoch": 321
      , "slot": 137140009
      , "block_time": "2026-10-24T06:26:49Z"
      , "lag_seconds": 43
      , "is_ready": true
      , "source": "cardano-db-sync"
      }
  , "attest_lag_seconds": 0
  , "attestation":
      { "slot": 137140009
      , "kupo_tip_slot": 137140009
      , "lag_seconds": 0
      , "state": "following"
      , "last_sync_at": "2026-10-24T06:27:22.960784Z"
      , "is_ready": true
      , "policy_id": "648c6a732aa55efec29815bdd25cf65c565cf92619aadde1d31496d3"
      , "last_error": null
      , "source": "attest-sync/kupo"
      }
  , "drep_distr_epoch": 321
  , "amber_lag_seconds": 120
  , "ready_max_lag_seconds": 300
  , "metrics_as_of_epoch": 321
  }
  """

-- | `GET /pages/dashboard` pe preprod, 2026-10-25, cu parametrii impliciți (`top_limit` 10,
-- | `closing_soon_limit` 5, `epochs` 20).
-- |
-- | Două cifre din el merită citite împreună: `total_dreps` 294 și `active_dreps` 17 +
-- | `inactive_dreps` 187 = 204. Diferența de 90 sunt DRep-ii cu status `unknown`. De aceea linkul
-- | de pe dashboard spre listă poartă explicit `status=active&status=inactive`: altfel utilizatorul
-- | dă clic pe „204" și aterizează pe o listă de 294.
dashboardFixture :: String
dashboardFixture =
  """
  {
    "epoch": 321,
    "total_dreps": 294,
    "active_dreps": 17,
    "inactive_dreps": 187,
    "unknown_dreps": 90,
    "retired_dreps": 526,
    "power_epoch": 321,
    "drep_power_lovelace": 505754377083269,
    "always_abstain_lovelace": 432909247919877,
    "always_no_confidence_lovelace": 330754812982,
    "total_actions": 131,
    "actions_in_flight": 7,
    "treasury_requested_lovelace": 656466092110010,
    "treasury_enacted_lovelace": 0,
    "actions_by_type": [
      [
        "hard_fork_initiation",
        4
      ],
      [
        "info_action",
        17
      ],
      [
        "new_committee",
        8
      ],
      [
        "new_constitution",
        2
      ],
      [
        "no_confidence",
        2
      ],
      [
        "parameter_change",
        16
      ],
      [
        "treasury_withdrawals",
        82
      ]
    ],
    "actions_by_state": [
      [
        "dropped",
        6
      ],
      [
        "enacted",
        11
      ],
      [
        "expired",
        107
      ],
      [
        "proposed",
        7
      ],
      [
        "ratified",
        0
      ]
    ],
    "participation_by_epoch": [
      {
        "epoch": 302,
        "dreps_with_power": 169,
        "dreps_voted": 35,
        "votes_cast": 35,
        "participation_rate": 0.20710059171597633
      },
      {
        "epoch": 303,
        "dreps_with_power": 171,
        "dreps_voted": 16,
        "votes_cast": 16,
        "participation_rate": 0.0935672514619883
      },
      {
        "epoch": 304,
        "dreps_with_power": 171,
        "dreps_voted": 3,
        "votes_cast": 3,
        "participation_rate": 0.017543859649122806
      },
      {
        "epoch": 305,
        "dreps_with_power": 172,
        "dreps_voted": 1,
        "votes_cast": 1,
        "participation_rate": 0.005813953488372093
      },
      {
        "epoch": 306,
        "dreps_with_power": 173,
        "dreps_voted": 31,
        "votes_cast": 32,
        "participation_rate": 0.1791907514450867
      },
      {
        "epoch": 307,
        "dreps_with_power": 176,
        "dreps_voted": 11,
        "votes_cast": 13,
        "participation_rate": 0.0625
      },
      {
        "epoch": 308,
        "dreps_with_power": 176,
        "dreps_voted": 40,
        "votes_cast": 40,
        "participation_rate": 0.22727272727272727
      },
      {
        "epoch": 309,
        "dreps_with_power": 176,
        "dreps_voted": 4,
        "votes_cast": 4,
        "participation_rate": 0.022727272727272728
      },
      {
        "epoch": 310,
        "dreps_with_power": 177,
        "dreps_voted": 15,
        "votes_cast": 17,
        "participation_rate": 0.0847457627118644
      },
      {
        "epoch": 311,
        "dreps_with_power": 177,
        "dreps_voted": 0,
        "votes_cast": 0,
        "participation_rate": 0.0
      },
      {
        "epoch": 312,
        "dreps_with_power": 178,
        "dreps_voted": 7,
        "votes_cast": 13,
        "participation_rate": 0.03932584269662921
      },
      {
        "epoch": 313,
        "dreps_with_power": 181,
        "dreps_voted": 17,
        "votes_cast": 31,
        "participation_rate": 0.09392265193370165
      },
      {
        "epoch": 314,
        "dreps_with_power": 181,
        "dreps_voted": 1,
        "votes_cast": 1,
        "participation_rate": 0.0055248618784530384
      },
      {
        "epoch": 315,
        "dreps_with_power": 182,
        "dreps_voted": 2,
        "votes_cast": 2,
        "participation_rate": 0.01098901098901099
      },
      {
        "epoch": 316,
        "dreps_with_power": 182,
        "dreps_voted": 2,
        "votes_cast": 2,
        "participation_rate": 0.01098901098901099
      },
      {
        "epoch": 317,
        "dreps_with_power": 186,
        "dreps_voted": 17,
        "votes_cast": 18,
        "participation_rate": 0.0913978494623656
      },
      {
        "epoch": 318,
        "dreps_with_power": 187,
        "dreps_voted": 26,
        "votes_cast": 26,
        "participation_rate": 0.13903743315508021
      },
      {
        "epoch": 319,
        "dreps_with_power": 186,
        "dreps_voted": 24,
        "votes_cast": 24,
        "participation_rate": 0.12903225806451613
      },
      {
        "epoch": 320,
        "dreps_with_power": 185,
        "dreps_voted": 16,
        "votes_cast": 16,
        "participation_rate": 0.08648648648648649
      },
      {
        "epoch": 321,
        "dreps_with_power": 185,
        "dreps_voted": 9,
        "votes_cast": 9,
        "participation_rate": 0.04864864864864865
      }
    ],
    "top_dreps_by_power": [
      {
        "id": "drep1ygzlzlzj8r9c3zutlgh9ugqx958cwr6q704xtt9j5uf4lzsz9rwhm",
        "hex": "05f17c5238cb888b8bfa2e5e20062d0f870f40f3ea65acb2a7135f8a",
        "has_script": false,
        "status": "active",
        "is_active": true,
        "active_until_epoch": 324,
        "given_name": null,
        "image_url": null,
        "language": null,
        "anchor_status": null,
        "registered_at": "2025-07-14T05:02:00Z",
        "age_days": 468,
        "voting_power": 400644627419166,
        "voting_power_epoch": 321,
        "delegator_count": 19,
        "eligible_actions": 105,
        "votes_cast": 10,
        "participation_rate": 0.09523809523809523,
        "rationale_rate": 0.0,
        "open_actions_unvoted": 7,
        "last_vote_at": "2026-07-29T19:21:51Z",
        "as_of_epoch": 321
      },
      {
        "id": "drep1yg3j4dkpz3j0eh4e9d5l3uy43sf5ndz2wv4c2fywgdcu4wsjmj5wp",
        "hex": "232ab6c11464fcdeb92b69f8f0958c1349b44a732b85248e4371caba",
        "has_script": false,
        "status": "inactive",
        "is_active": false,
        "active_until_epoch": 296,
        "given_name": null,
        "image_url": null,
        "language": null,
        "anchor_status": "unreachable",
        "registered_at": "2026-01-20T12:15:56Z",
        "age_days": 277,
        "voting_power": 60594158706858,
        "voting_power_epoch": 321,
        "delegator_count": 417,
        "eligible_actions": 36,
        "votes_cast": 0,
        "participation_rate": 0.0,
        "rationale_rate": null,
        "open_actions_unvoted": 7,
        "last_vote_at": null,
        "as_of_epoch": 321
      },
      {
        "id": "drep1ygnl9fjlz3pahx5vd2m6y4ya0562n8ttqzss9ncacu6l6pqwm2php",
        "hex": "27f2a65f1443db9a8c6ab7a2549d7d34a99d6b00a102cf1dc735fd04",
        "has_script": false,
        "status": "inactive",
        "is_active": false,
        "active_until_epoch": 199,
        "given_name": null,
        "image_url": null,
        "language": null,
        "anchor_status": null,
        "registered_at": "2024-11-09T09:41:55Z",
        "age_days": 715,
        "voting_power": 7264462090316,
        "voting_power_epoch": 321,
        "delegator_count": 5,
        "eligible_actions": 119,
        "votes_cast": 0,
        "participation_rate": 0.0,
        "rationale_rate": null,
        "open_actions_unvoted": 7,
        "last_vote_at": null,
        "as_of_epoch": 321
      }
    ],
    "closing_soon": [
      {
        "id": "6989c68f04b7452c22de9c0b95f40960cc17fab73bc2365f51d46da31db2c75e#0",
        "bech32": "gov_action1dxyudrcykazjcgk7ns9etaqfvrxp074h80prvh6363k6x8djca0qqpx4v94",
        "type": "no_confidence",
        "title": null,
        "abstract": null,
        "anchor_status": "unreachable",
        "proposed_at": {
          "slot": 135501681,
          "epoch": 317,
          "time": "2026-10-05T07:21:21Z",
          "tx_hash": "6989c68f04b7452c22de9c0b95f40960cc17fab73bc2365f51d46da31db2c75e"
        },
        "expires_epoch": 324,
        "last_votable_epoch": 323,
        "lifecycle": {
          "state": "proposed",
          "ratified_epoch": null,
          "enacted_epoch": null,
          "expired_epoch": null,
          "dropped_epoch": null,
          "formula_id": "gov_action_state_v1"
        },
        "deposit": 1000000000,
        "return_address": "stake_test1uzrr46pd4wn2qpzvv5fpdeycndzsgjc899jn8e4rmten3ngcgm3f4",
        "treasury_amount": null,
        "votes_cast": 0
      },
      {
        "id": "e5d288b5ce81c2b04bba8b5d3d9a69ac9a078544022fd0ec123fa5717d6f23f0#0",
        "bech32": "gov_action1uhfg3dwws8ptqja63dwnmxnf4jdq0p2yqghapmqj87jhzlt0y0cqqauysd8",
        "type": "hard_fork_initiation",
        "title": null,
        "abstract": null,
        "anchor_status": "unreachable",
        "proposed_at": {
          "slot": 135504192,
          "epoch": 317,
          "time": "2026-10-05T08:03:12Z",
          "tx_hash": "e5d288b5ce81c2b04bba8b5d3d9a69ac9a078544022fd0ec123fa5717d6f23f0"
        },
        "expires_epoch": 324,
        "last_votable_epoch": 323,
        "lifecycle": {
          "state": "proposed",
          "ratified_epoch": null,
          "enacted_epoch": null,
          "expired_epoch": null,
          "dropped_epoch": null,
          "formula_id": "gov_action_state_v1"
        },
        "deposit": 1000000000,
        "return_address": "stake_test1uzrr46pd4wn2qpzvv5fpdeycndzsgjc899jn8e4rmten3ngcgm3f4",
        "treasury_amount": null,
        "votes_cast": 0
      }
    ]
  }
  """

-- | `GET /pages/drep-explorer?limit=4&order_by=voting_power&sort_order=desc` pe preprod,
-- | 2026-10-25.
-- |
-- | Trei fapte măsurate pe care ecranul trebuie să le respecte, și pe care fixtura le păstrează:
-- |
-- |   * `status_facets` însumează 820, iar `total` e 294. Facetele se numără fiecare cu propriul
-- |     predicat scos (semantică standard de facet), deci __nu se calculează procente din ele__;
-- |   * `anchor_facets` însumează 131: un DRep fără ancoră nu intră în nicio categorie;
-- |   * `power_buckets` __da__ însumează la 294, pentru că fiecare DRep cade în exact un bucket.
-- |     E singura desfășurare din care un procent are sens.
-- |
-- | `language_facets` are o cheie goală (`""`, 4 DRep-i): limba e un câmp liber din metadate, iar
-- | șirul gol e o valoare pe care o scrie cineva, nu absența valorii.
drepExplorerFixture :: String
drepExplorerFixture =
  """
  {
    "items": [
      {
        "id": "drep1ygzlzlzj8r9c3zutlgh9ugqx958cwr6q704xtt9j5uf4lzsz9rwhm",
        "hex": "05f17c5238cb888b8bfa2e5e20062d0f870f40f3ea65acb2a7135f8a",
        "has_script": false,
        "status": "active",
        "is_active": true,
        "active_until_epoch": 324,
        "given_name": null,
        "image_url": null,
        "language": null,
        "anchor_status": null,
        "registered_at": "2025-07-14T05:02:00Z",
        "age_days": 468,
        "voting_power": 400644627419166,
        "voting_power_epoch": 321,
        "delegator_count": 19,
        "eligible_actions": 105,
        "votes_cast": 10,
        "participation_rate": 0.09523809523809523,
        "rationale_rate": 0.0,
        "open_actions_unvoted": 7,
        "last_vote_at": "2026-07-29T19:21:51Z",
        "as_of_epoch": 321
      },
      {
        "id": "drep1yg3j4dkpz3j0eh4e9d5l3uy43sf5ndz2wv4c2fywgdcu4wsjmj5wp",
        "hex": "232ab6c11464fcdeb92b69f8f0958c1349b44a732b85248e4371caba",
        "has_script": false,
        "status": "inactive",
        "is_active": false,
        "active_until_epoch": 296,
        "given_name": null,
        "image_url": null,
        "language": null,
        "anchor_status": "unreachable",
        "registered_at": "2026-01-20T12:15:56Z",
        "age_days": 277,
        "voting_power": 60594158706858,
        "voting_power_epoch": 321,
        "delegator_count": 417,
        "eligible_actions": 36,
        "votes_cast": 0,
        "participation_rate": 0.0,
        "rationale_rate": null,
        "open_actions_unvoted": 7,
        "last_vote_at": null,
        "as_of_epoch": 321
      },
      {
        "id": "drep1ygnl9fjlz3pahx5vd2m6y4ya0562n8ttqzss9ncacu6l6pqwm2php",
        "hex": "27f2a65f1443db9a8c6ab7a2549d7d34a99d6b00a102cf1dc735fd04",
        "has_script": false,
        "status": "inactive",
        "is_active": false,
        "active_until_epoch": 199,
        "given_name": null,
        "image_url": null,
        "language": null,
        "anchor_status": null,
        "registered_at": "2024-11-09T09:41:55Z",
        "age_days": 715,
        "voting_power": 7264462090316,
        "voting_power_epoch": 321,
        "delegator_count": 5,
        "eligible_actions": 119,
        "votes_cast": 0,
        "participation_rate": 0.0,
        "rationale_rate": null,
        "open_actions_unvoted": 7,
        "last_vote_at": null,
        "as_of_epoch": 321
      },
      {
        "id": "drep1yfleuad6rwdgk5y640aa3d4jc3gdukyq5vcxc84lx8mlklcw50hva",
        "hex": "7f9e75ba1b9a8b509aabfbd8b6b2c450de5880a3306c1ebf31f7fb7f",
        "has_script": false,
        "status": "inactive",
        "is_active": false,
        "active_until_epoch": 297,
        "given_name": null,
        "image_url": null,
        "language": null,
        "anchor_status": null,
        "registered_at": "2026-03-18T10:32:09Z",
        "age_days": 221,
        "voting_power": 7009495872731,
        "voting_power_epoch": 321,
        "delegator_count": 1,
        "eligible_actions": 36,
        "votes_cast": 0,
        "participation_rate": 0.0,
        "rationale_rate": null,
        "open_actions_unvoted": 7,
        "last_vote_at": null,
        "as_of_epoch": 321
      }
    ],
    "total": 294,
    "limit": 4,
    "offset": 0,
    "epoch": 321,
    "status_facets": [
      [
        "active",
        17
      ],
      [
        "inactive",
        187
      ],
      [
        "retired",
        526
      ],
      [
        "unknown",
        90
      ]
    ],
    "anchor_facets": [
      [
        "unreachable",
        51
      ],
      [
        "valid",
        50
      ],
      [
        "hash_mismatch",
        26
      ],
      [
        "invalid_schema",
        4
      ]
    ],
    "language_facets": [
      [
        "en-us",
        50
      ],
      [
        "",
        4
      ]
    ],
    "power_buckets": [
      {
        "lo": 0,
        "hi": 1,
        "count": 109
      },
      {
        "lo": 1,
        "hi": 1000000000,
        "count": 28
      },
      {
        "lo": 1000000000,
        "hi": 10000000000,
        "count": 53
      },
      {
        "lo": 10000000000,
        "hi": 100000000000,
        "count": 69
      },
      {
        "lo": 100000000000,
        "hi": 1000000000000,
        "count": 23
      },
      {
        "lo": 1000000000000,
        "hi": null,
        "count": 12
      }
    ]
  }
  """

-- | `GET /pages/drep/drep1ydmraa6kv8cvmry059v608tehl50nfmg0z764lmsqkvwurs40sw2z` pe preprod,
-- | 2026-10-25. Ales dintre cei 294 pentru că e cazul __greu__: DRep script, cu ancoră validă, cu
-- | două referințe externe, cu voturi pe patru tipuri de acțiuni din șapte — adică exact ecranul pe
-- | care se vede dacă randarea unui document străin e făcută cu grijă.
-- |
-- | `power_by_epoch` e ultimele 20 de puncte din cele 94 reale. `top_delegators` sunt toți cinci,
-- | __inclusiv al cincilea, care are `lovelace: null`__: un delegator pentru care epoca nu are
-- | stake înregistrat (limitarea §8.3 din contractul API-ului). Fixtura de dinainte îi tăia, și
-- | exact de aceea a trecut testele și a căzut în browser pe serverul adevărat.
drepDetailFixture :: String
drepDetailFixture =
  """
  {
    "drep": {
      "id": "drep1ydmraa6kv8cvmry059v608tehl50nfmg0z764lmsqkvwurs40sw2z",
      "hex": "763ef75661f0cd8c8fa159a79d79bfe8f9a76878bdaaff700598ee0e",
      "has_script": true,
      "status": "inactive",
      "is_active": false,
      "active_until_epoch": 189,
      "given_name": "Logical Mechanism dRep",
      "image_url": "https://www.logicalmechanism.io/img/fullLogo.png",
      "language": "en-us",
      "anchor_status": "valid",
      "registered_at": "2024-09-06T23:10:12Z",
      "age_days": 778,
      "voting_power": 5942176444940,
      "voting_power_epoch": 321,
      "delegator_count": 5,
      "eligible_actions": 120,
      "votes_cast": 1,
      "participation_rate": 0.008333333333333333,
      "rationale_rate": 0.0,
      "open_actions_unvoted": 7,
      "last_vote_at": "2024-09-06T23:22:48Z",
      "as_of_epoch": 321
    },
    "metrics": {
      "as_of_epoch": 321,
      "eligible_actions": 120,
      "votes_cast": 1,
      "open_actions_unvoted": 7,
      "participation_rate": 0.008333333333333333,
      "rationale_verified": 0,
      "rationale_inline": 0,
      "rationale_unverified": 0,
      "rationale_pending": 0,
      "rationale_absent": 1,
      "rationale_cip100_valid": 0,
      "rationale_rate": 0.0,
      "vote_latency_median_hours": 0.05444444444444444,
      "vote_latency_p90_hours": 0.05444444444444444,
      "vote_latency_sample": 1,
      "age_days": 778,
      "final_votes": {
        "yes": 1,
        "no": 0,
        "abstain": 0
      },
      "votes_by_type": [
        [
          "hard_fork_initiation",
          {
            "eligible_actions": 2,
            "votes_cast": 0,
            "yes": 0,
            "no": 0,
            "abstain": 0,
            "participation_rate": 0.0
          }
        ],
        [
          "info_action",
          {
            "eligible_actions": 17,
            "votes_cast": 1,
            "yes": 1,
            "no": 0,
            "abstain": 0,
            "participation_rate": 0.058823529411764705
          }
        ],
        [
          "new_committee",
          {
            "eligible_actions": 7,
            "votes_cast": 0,
            "yes": 0,
            "no": 0,
            "abstain": 0,
            "participation_rate": 0.0
          }
        ],
        [
          "new_constitution",
          {
            "eligible_actions": 1,
            "votes_cast": 0,
            "yes": 0,
            "no": 0,
            "abstain": 0,
            "participation_rate": 0.0
          }
        ],
        [
          "no_confidence",
          {
            "eligible_actions": 1,
            "votes_cast": 0,
            "yes": 0,
            "no": 0,
            "abstain": 0,
            "participation_rate": 0.0
          }
        ],
        [
          "parameter_change",
          {
            "eligible_actions": 11,
            "votes_cast": 0,
            "yes": 0,
            "no": 0,
            "abstain": 0,
            "participation_rate": 0.0
          }
        ],
        [
          "treasury_withdrawals",
          {
            "eligible_actions": 81,
            "votes_cast": 0,
            "yes": 0,
            "no": 0,
            "abstain": 0,
            "participation_rate": 0.0
          }
        ]
      ],
      "formula_ids": [
        "participation_rate_v1",
        "rationale_rate_v1",
        "age_days_v1",
        "delegator_retention_rate_v1",
        "vote_latency_median_hours_v1",
        "votes_by_type_v1"
      ]
    },
    "delegator_stats": {
      "delegator_count": 5,
      "delegator_count_prev": 5,
      "delegators_retained": 5,
      "delegators_joined": 0,
      "delegators_left": 0,
      "delegator_retention_rate": 1.0,
      "window_epochs": 10
    },
    "power_by_epoch": [
      {
        "epoch": 302,
        "lovelace": 5889967679740,
        "delegator_count": 5
      },
      {
        "epoch": 303,
        "lovelace": 5874056067112,
        "delegator_count": 5
      },
      {
        "epoch": 304,
        "lovelace": 5874836087448,
        "delegator_count": 5
      },
      {
        "epoch": 305,
        "lovelace": 5879754429475,
        "delegator_count": 5
      },
      {
        "epoch": 306,
        "lovelace": 5883923005781,
        "delegator_count": 5
      },
      {
        "epoch": 307,
        "lovelace": 5888569602056,
        "delegator_count": 5
      },
      {
        "epoch": 308,
        "lovelace": 5893190135192,
        "delegator_count": 5
      },
      {
        "epoch": 309,
        "lovelace": 5897720675965,
        "delegator_count": 5
      },
      {
        "epoch": 310,
        "lovelace": 5901872333057,
        "delegator_count": 5
      },
      {
        "epoch": 311,
        "lovelace": 5906522519873,
        "delegator_count": 5
      },
      {
        "epoch": 312,
        "lovelace": 5910755571684,
        "delegator_count": 5
      },
      {
        "epoch": 313,
        "lovelace": 5910762282359,
        "delegator_count": 5
      },
      {
        "epoch": 314,
        "lovelace": 5910770233192,
        "delegator_count": 5
      },
      {
        "epoch": 315,
        "lovelace": 5914902920642,
        "delegator_count": 5
      },
      {
        "epoch": 316,
        "lovelace": 5919918376352,
        "delegator_count": 5
      },
      {
        "epoch": 317,
        "lovelace": 5924415104092,
        "delegator_count": 5
      },
      {
        "epoch": 318,
        "lovelace": 5928925649832,
        "delegator_count": 5
      },
      {
        "epoch": 319,
        "lovelace": 5933433550288,
        "delegator_count": 5
      },
      {
        "epoch": 320,
        "lovelace": 5937875560062,
        "delegator_count": 5
      },
      {
        "epoch": 321,
        "lovelace": 5942176444940,
        "delegator_count": 5
      }
    ],
    "top_delegators": [
      {
        "stake_address": "stake_test1uzrvw62pn24xw0yk8ksyuj6m4ezg6jgw9n4vjqktstjd5aspv59nv",
        "lovelace": 5912487235860,
        "delegated_at": {
          "slot": 69983290,
          "epoch": 165,
          "time": "2024-09-06T23:48:10Z",
          "tx_hash": "7215b4e94e30d1341b1c30f9defacfa9a583a2ef0973dcd3e2b862d9f5e386da"
        },
        "is_current": true
      },
      {
        "stake_address": "stake_test1ur7sufjy8lfactkprnwl5x7mjn0ugajqg920n6uv4g7l68cra6p74",
        "lovelace": 11647105014,
        "delegated_at": {
          "slot": 71680542,
          "epoch": 169,
          "time": "2024-09-26T15:15:42Z",
          "tx_hash": "2d91ed34e62bcca5b1e80673044aec56ce2da17794be843a96e8784fcc97ca1a"
        },
        "is_current": true
      },
      {
        "stake_address": "stake_test1uzl65wzu364hh0wxex94qsf5xkeaq2mnmc7xgnsnsjuqr4qruvxwu",
        "lovelace": 8863539868,
        "delegated_at": {
          "slot": 69981608,
          "epoch": 165,
          "time": "2024-09-06T23:20:08Z",
          "tx_hash": "46bd643c23eabbce70deebbf23127022f109f7813086b123b4cedca8f3d95983"
        },
        "is_current": true
      },
      {
        "stake_address": "stake_test1upqt8jvd8d045a6gs2wkzt57rnx47s5ewz4un2l746r847g7hgw24",
        "lovelace": 180912096,
        "delegated_at": {
          "slot": 69981238,
          "epoch": 165,
          "time": "2024-09-06T23:13:58Z",
          "tx_hash": "fdd0e44251da1b0b6b6c9d8e92ad0010d3e13640f608ccf91c18278b9ab99861"
        },
        "is_current": true
      },
      {
        "stake_address": "stake_test1uzyp0n0lqk65g9wae0uhn3fdzevww4u7w665w46wsdmeaysjvtvpu",
        "lovelace": null,
        "delegated_at": {
          "slot": 88520092,
          "epoch": 208,
          "time": "2025-04-09T12:54:52Z",
          "tx_hash": "bcfd8c71d322df7205013b0a5f5f418f80b733f95c37b31109557bfc3022317a"
        },
        "is_current": true
      }
    ],
    "updates": [
      {
        "kind": "updated",
        "at": {
          "slot": 69981800,
          "epoch": 165,
          "time": "2024-09-06T23:23:20Z",
          "tx_hash": "ebab27b88379f662d5bdcd2db7c0be391fd94674a889255411d540b6684e5c13"
        },
        "deposit": null,
        "anchor_url": "https://www.logicalmechanism.io/drepTestnet",
        "anchor_status": "valid"
      },
      {
        "kind": "registered",
        "at": {
          "slot": 69981012,
          "epoch": 165,
          "time": "2024-09-06T23:10:12Z",
          "tx_hash": "744fb092ab6d8a4d8ca8f66ea3c0abb6b9d49381205aa41c75c8597e91137948"
        },
        "deposit": 500000000,
        "anchor_url": null,
        "anchor_status": null
      }
    ],
    "anchor_content": {
      "given_name": "Logical Mechanism dRep",
      "objectives": "We want to provide expert consulting, comprehensive knowledge, and in-depth research into the future of Cardano.",
      "motivations": "We are a technical consulting company specializing in open-sourced decentralized applications for the everyday user. We know Cardano inwards and out.",
      "qualifications": "We are Plutus pioneers, dApp developers, stake pool operators, and open-source contributors. We know Cardano.",
      "image_url": "https://www.logicalmechanism.io/img/fullLogo.png",
      "payment_address": "addr_test1qrvnxkaylr4upwxfxctpxpcumj0fl6fdujdc72j8sgpraa9l4gu9er4t0w7udjvt2pqngddn6q4h8h3uv38p8p9cq82qav4lmp",
      "references": [
        {
          "label": "The Logical Mechanism Website",
          "uri": "https://www.logicalmechanism.io/"
        },
        {
          "label": "The Logical Mechanism GitHub",
          "uri": "https://github.com/logical-mechanism"
        }
      ]
    }
  }
  """
