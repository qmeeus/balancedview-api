# Application programming interface

**This repository is the application programming interface of a larger software located [here](https://github.com/qmeeus/balanced-view). For more information about the whole project, please refer to the parent repository.**

**Before starting, make sure that the folder `api/resources` contains 2 files: `news_apikey` and `ibm-credentials.env`, otherwise, you won't go very far.**

The API relies on more complex components and deserves a more exhaustive explanation. As mentioned earlier, it currently has two endpoints, one to find relevant articles and one to analyse texts. Each endpoint accepts a number of options that should be provided as a JSON document. Default options that apply to both endpoints include:

- `output_language`: the language in which the results should be returned (not implemented);
- `search_languages`: a list of relevant languages to search the database;
- `groupby_options`: a set of options to organise the results in groups:
  - `key`: a string that correspond to the name of the field in the database to group the data;
  - `default`: a string that correspond to the name of the default group;
  - `orderby`: a string that correspond to the name of the field used to sort the results;
  - `reverse`: a boolean field that decides whether the results should be sorted in reverse order;
  - `max_results_per_group`: an integer to limit the number of results;
  - `groups`: a list of groups, composed of a name for the group and a value to match each result.

## `/articles` endpoint
The first endpoint is available at `<api-url>/articles` and has the following options:
- `terms`: a list of strings that corresponds to the query terms to be matched against the database;
- `source_language`: a string corresponding to the language ISO code of the terms.

When a request comes in through this endpoint, the terms are translated in each of the requested search languages and a number of queries are built, one for each language, to match against document in the database. An example query is showed below (see [Elasticsearch Query DSL documentation](https://www.elastic.co/guide/en/elasticsearch/reference/current/query-filter-context.html) for background on what this means):

```json
{
  "query": {
    "bool": {
      "must": [{"match": {"language": "nl"}}],
      "minimum_should_match": 2,
      "should": [
        {"multi_match": {"fields": ["body", "title"], "type": "phrase", "query": "Midi"}},
        {"multi_match": {"fields": ["body", "title"], "type": "phrase", "query": "Noord"}},
        {"multi_match": {"fields": ["body", "title"], "type": "phrase", "query": "kruising"}},
        {"multi_match": {"fields": ["body", "title"], "type": "phrase", "query": "werken"}},
        {"multi_match": {"fields": ["body", "title"], "type": "phrase", "query": "storingen"}}
      ]
    }
  }
}
```

The `minimum_should_match` argument is calculated according to this rule: `minimum_should_match = int(0.5 * len(terms))`. If matching documents are found, they are formatted according to the `groupby` options, if provided, and returned to the client. Otherwise, an error message is returned.

## `/analysis` endpoint
The second endpoint is available at `<api-url>/analysis` and has the following options:

- `input_text`: a string, the text on which the analysis should be performed;
- `related`: a boolean field that decides whether to include output from the article endpoint or not.

When a requests comes in, the input text is cleaned (at the moment, the only operation is to redundant spaces) and a hash is calculated on it. We try to match the hash to an existing document id in the database. If it is found, the document is retrieved with the analysis results. This allows to prevent the same expensive operations to be recalculated multiple time and save precious CPU time. If the document was not seen before, we use IBM Language Translator to identify the language and load the corresponding `spacy` model. We filter stop words, extract tokens, part-of-speech tags and named entities from the text and pass them to `TextRank` algorithm which builds a graph that models token co-occurences. The `TextRank` score is calculated based on the centrality of each token in the text. The measure of centrality denotes of how many nodes a node points to and how many nodes points to it. If necessary, we get related articles using the identified language and the top keywords found by `TextRank` as query terms for the `articles` endpoint.

**A note on efficiency:** `Spacy` models can be relatively expensive to load. For this reason, if they were loaded at each request, the website would be very slow, causing timeout errors most of the time. For this reason, the decision was made to load the models when the container starts and store them in a dictionary. This has a considerable impact on memory but relieves a great deal of the pressure on the CPU. Nonetheless, this limits possibilities for adding new languages because that means that each new model have to be stored in memory. For example, if `gunicorn` is using 3 workers and there are 3 languages models, 9 models in total are loaded at boot. Workarounds exists but might require a lot of changes and expertise. Feel free to do a merge request.

## Data provider
The database is populated using two methods:
- By calling the [NewsAPI](https://newsapi.org)'s `top-headlines` endpoint, using the default sources located in `api.data_provider.sources.newsapi.NewsAPIClient.DEFAULT_SOURCES`. A list of available sources is given in `api/data_provider/sources/resources/api_sources.json` and can be updated using the method `get_sources` from the `NewsAPIClient`.
- By fetching RSS feeds from the sources available at `api/data_provider/sources/resources/rss_sources.json`. New sources can be added simply by appending to this file. **Make sure to respect the syntax, JSON does not forgive!** The requests to one source's categories are implemented using multi-threading because it's cool and it's fast. 

The module `api.data_provider` is called at regular intervals using a `cronjob` to update the database (check the `docker-entrypoint.sh` to see how the cronjob is created and `api.data_provider.__main__` to see what exactly is running). Note that you need an instance of Elasticsearch running and the accesses must be configured.
